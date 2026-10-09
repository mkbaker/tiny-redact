import AppKit
import SwiftUI

final class ReviewModel: ObservableObject {
    let image: CGImage
    @Published var detections: [Detection]
    @Published var drawLabels: Bool
    /// In-progress drag rectangle (view coordinates). Kept here rather than in @State so no SwiftUI macros are needed.
    @Published var dragRect: CGRect?

    init(image: CGImage, detections: [Detection], drawLabels: Bool) {
        self.image = image
        self.detections = detections
        self.drawLabels = drawLabels
    }

    var enabledCount: Int { detections.filter(\.enabled).count }
}

struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    var onCancel: () -> Void
    var onCopy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let iw = CGFloat(model.image.width), ih = CGFloat(model.image.height)
                let scale = min(geo.size.width / iw, geo.size.height / ih)
                let size = CGSize(width: iw * scale, height: ih * scale)

                ZStack(alignment: .topLeading) {
                    Image(decorative: model.image, scale: 1)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .gesture(addBoxGesture(scale: scale, bounds: size))

                    ForEach($model.detections) { $d in
                        BoxView(detection: d, scale: scale, showLabel: model.drawLabels)
                            .onTapGesture { d.enabled.toggle() }
                    }

                    if let r = model.dragRect {
                        Rectangle()
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)

            Divider()

            HStack(spacing: 12) {
                Text(statusText).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Toggle("Labels", isOn: $model.drawLabels).toggleStyle(.checkbox)
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Copy Redacted", action: onCopy).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private var statusText: String {
        let n = model.enabledCount
        let found = n == 0 ? "Nothing detected" : "\(n) redaction\(n == 1 ? "" : "s")"
        return "\(found) · click a box to toggle · drag to add one"
    }

    private func addBoxGesture(scale: CGFloat, bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                model.dragRect = CGRect(x: min(v.startLocation.x, v.location.x),
                                  y: min(v.startLocation.y, v.location.y),
                                  width: abs(v.location.x - v.startLocation.x),
                                  height: abs(v.location.y - v.startLocation.y))
                    .intersection(CGRect(origin: .zero, size: bounds))
            }
            .onEnded { _ in
                if let r = model.dragRect, !r.isNull, r.width > 3, r.height > 3 {
                    model.detections.append(Detection(
                        rect: CGRect(x: r.minX / scale, y: r.minY / scale,
                                     width: r.width / scale, height: r.height / scale),
                        kind: .manual, text: "", label: "Redacted"))
                }
                model.dragRect = nil
            }
    }
}

private struct BoxView: View {
    let detection: Detection
    let scale: CGFloat
    let showLabel: Bool

    var body: some View {
        let r = CGRect(x: detection.rect.minX * scale, y: detection.rect.minY * scale,
                       width: detection.rect.width * scale, height: detection.rect.height * scale)
        ZStack {
            if detection.enabled {
                Rectangle().fill(Color(white: 0.12))
                if showLabel {
                    Text(detection.label)
                        .font(.system(size: max(7, min(r.height * 0.6, 14)), weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 2)
                }
            } else {
                Rectangle().fill(Color.red.opacity(0.08))
                Rectangle().strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .offset(x: r.minX, y: r.minY)
        .help(detection.enabled ? "\(detection.label) — click to un-redact" : "Not redacted — click to redact")
    }
}

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private var completion: ((ReviewModel?) -> Void)?
    let model: ReviewModel

    init(model: ReviewModel, completion: @escaping (ReviewModel?) -> Void) {
        self.model = model
        self.completion = completion

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let w = min(max(CGFloat(model.image.width) / backing + 24, 560), screen.width * 0.85)
        let h = min(max(CGFloat(model.image.height) / backing + 24 + 56, 320), screen.height * 0.85)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Review Redactions"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        window.delegate = self

        let view = ReviewView(model: model,
                              onCancel: { [weak self] in self?.finish(accepted: false) },
                              onCopy: { [weak self] in self?.finish(accepted: true) })
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func finish(accepted: Bool) {
        let c = completion
        completion = nil
        window?.close()
        c?(accepted ? model : nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let c = completion {
            completion = nil
            c(nil)
        }
    }
}
