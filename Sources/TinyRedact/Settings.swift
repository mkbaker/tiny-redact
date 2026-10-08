import SwiftUI

enum Prefs {
    private static let d = UserDefaults.standard

    static func register() {
        d.register(defaults: [
            "names": true, "nameHeuristics": true, "emails": true, "phones": true, "addresses": false,
            "propagate": true, "labels": true, "review": true, "save": false,
            "alwaysRedact": "", "neverRedact": "",
        ])
    }

    static var options: DetectorOptions {
        DetectorOptions(
            names: d.bool(forKey: "names"),
            nameHeuristics: d.bool(forKey: "nameHeuristics"),
            emails: d.bool(forKey: "emails"),
            phones: d.bool(forKey: "phones"),
            addresses: d.bool(forKey: "addresses"),
            propagate: d.bool(forKey: "propagate"),
            alwaysRedact: list("alwaysRedact"),
            neverRedact: list("neverRedact")
        )
    }

    static var labels: Bool { d.bool(forKey: "labels") }
    static var review: Bool { d.bool(forKey: "review") }
    static var save: Bool { d.bool(forKey: "save") }

    private static func list(_ key: String) -> [String] {
        (d.string(forKey: key) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @AppStorage("names") private var names = true
    @AppStorage("nameHeuristics") private var nameHeuristics = true
    @AppStorage("emails") private var emails = true
    @AppStorage("phones") private var phones = true
    @AppStorage("addresses") private var addresses = false
    @AppStorage("propagate") private var propagate = true
    @AppStorage("labels") private var labels = true
    @AppStorage("review") private var review = true
    @AppStorage("save") private var save = false
    @AppStorage("alwaysRedact") private var alwaysRedact = ""
    @AppStorage("neverRedact") private var neverRedact = ""

    var body: some View {
        Form {
            Section("Detect") {
                Toggle("Person names (on-device language model)", isOn: $names)
                Toggle("Capitalized-name fallback for table cells / lists", isOn: $nameHeuristics)
                Toggle("Hide every other mention of a detected name", isOn: $propagate)
                Toggle("Email addresses", isOn: $emails)
                Toggle("Phone numbers", isOn: $phones)
                Toggle("Street addresses (single-line)", isOn: $addresses)
            }
            Section("Always redact — one per line (e.g. a customer or company name)") {
                TextEditor(text: $alwaysRedact).font(.body.monospaced()).frame(height: 70)
            }
            Section("Never redact — one per line (your app's labels that look like names)") {
                TextEditor(text: $neverRedact).font(.body.monospaced()).frame(height: 70)
            }
            Section("After capture") {
                Toggle("Review before copying (recommended)", isOn: $review)
                Toggle("Label boxes (Person 1, Email…) so Claude has context", isOn: $labels)
                Toggle("Also save a PNG to Pictures/TinyRedact", isOn: $save)
            }
            Section {
                Text("Shortcut: ⌃⌥⌘R. Text recognition and name detection run entirely on this Mac — nothing is uploaded. The unredacted capture is deleted as soon as it's loaded.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}
