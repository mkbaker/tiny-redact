import AppKit
import SwiftUI
import Carbon.HIToolbox
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var review: ReviewWindowController?
    private var settingsWindow: NSWindow?
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(busy: false)

        let menu = NSMenu()
        menu.addItem(item("Capture Redacted Screenshot", #selector(captureRegion), "r", [.control, .option, .command]))
        menu.addItem(item("Redact Image on Clipboard", #selector(redactClipboard)))
        menu.addItem(item("Redact Image File…", #selector(redactFile)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit TinyRedact", #selector(quit), "q"))
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | optionKey | controlKey)) { [weak self] in
            self?.captureRegion()
        }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    // MARK: - Sources

    @objc func captureRegion() {
        if let review { review.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            alert("TinyRedact needs Screen Recording permission",
                  "Turn it on in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen TinyRedact.")
            return
        }
        busy = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinyredact-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive (drag a region, Space toggles window mode, Esc cancels), -x no sound
        p.arguments = ["-i", "-x", url.path]
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                // Read the original into memory, then delete it right away so it never lingers on disk.
                let image = ImageLoader.load(url)
                try? FileManager.default.removeItem(at: url)
                self?.busy = false
                if let image { self?.process(image) } // nil = user pressed Esc
            }
        }
        do { try p.run() } catch {
            busy = false
            alert("Couldn't start screen capture", error.localizedDescription)
        }
    }

    @objc func redactClipboard() {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let image = ImageLoader.load(data)
        else { alert("There's no image on the clipboard."); return }
        process(image)
    }

    @objc func redactFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = ImageLoader.load(url) else { alert("Couldn't open that image."); return }
        process(image)
    }

    // MARK: - Pipeline

    private func process(_ image: CGImage) {
        setIcon(busy: true)
        let options = Prefs.options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let detections = (try? PIIDetector.detect(in: image, options: options)) ?? []
            Task { @MainActor in
                self?.setIcon(busy: false)
                self?.present(image, detections)
            }
        }
    }

    private func present(_ image: CGImage, _ detections: [Detection]) {
        guard Prefs.review else {
            deliver(image, detections, labels: Prefs.labels)
            return
        }
        let model = ReviewModel(image: image, detections: detections, drawLabels: Prefs.labels)
        let controller = ReviewWindowController(model: model) { [weak self] result in
            self?.review = nil
            if let result { self?.deliver(result.image, result.detections, labels: result.drawLabels) }
        }
        review = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func deliver(_ image: CGImage, _ detections: [Detection], labels: Bool) {
        guard let out = Redactor.render(image, detections: detections, drawLabels: labels),
              let png = Redactor.png(out)
        else { NSSound.beep(); return }

        let pb = NSPasteboard.general
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: out).representation(using: .tiff, properties: [:]) {
            pb.setData(tiff, forType: .tiff)
        }

        if Prefs.save {
            let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TinyRedact")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            try? png.write(to: dir.appendingPathComponent("Redacted \(f.string(from: Date())).png"))
        }

        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    // MARK: - UI bits

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "TinyRedact Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }

    private func setIcon(busy: Bool) {
        statusItem.button?.image = NSImage(systemSymbolName: busy ? "hourglass" : "eye.slash",
                                           accessibilityDescription: "TinyRedact")
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        return i
    }

    private func alert(_ text: String, _ info: String = "") {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = text
        a.informativeText = info
        a.runModal()
    }

    /// Menu-bar-only apps have no main menu, so ⌘C/⌘V wouldn't work in the Settings text boxes without this.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
