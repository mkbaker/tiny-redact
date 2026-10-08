import AppKit

// Headless mode for testing the detector on a file:
//   TinyRedact --redact input.png output.png
let args = CommandLine.arguments
if args.count >= 4, args[1] == "--redact" {
    exit(CLI.run(input: args[2], output: args[3]))
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    app.run() // never returns, so `delegate` stays alive
}
