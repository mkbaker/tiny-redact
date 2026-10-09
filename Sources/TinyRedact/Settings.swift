import SwiftUI

/// A setting's UserDefaults key and its default value — the only place either is written down.
struct Pref<Value> {
    let key: String
    let defaultValue: Value
}

enum Prefs {
    /// Every setting. SettingsView binds to these and `options` reads them, so the two can't drift apart.
    enum Key {
        static let names = Pref(key: "names", defaultValue: true)
        static let nameHeuristics = Pref(key: "nameHeuristics", defaultValue: true)
        static let emails = Pref(key: "emails", defaultValue: true)
        static let phones = Pref(key: "phones", defaultValue: true)
        static let addresses = Pref(key: "addresses", defaultValue: false)
        static let propagate = Pref(key: "propagate", defaultValue: true)
        static let labels = Pref(key: "labels", defaultValue: true)
        static let review = Pref(key: "review", defaultValue: true)
        static let save = Pref(key: "save", defaultValue: false)
        static let alwaysRedact = Pref(key: "alwaysRedact", defaultValue: "")
        static let neverRedact = Pref(key: "neverRedact", defaultValue: "")
    }

    /// The app bundle's CFBundleIdentifier (set in build.sh), which is also its defaults domain.
    static let appDomain = "com.local.tinyredact"

    /// The bare `.build/release/TinyRedact` used for `--redact` has no bundle id, so `.standard` would be a
    /// separate "TinyRedact" domain. Read the app's domain explicitly so the CLI sees the same settings.
    static let store: UserDefaults = Bundle.main.bundleIdentifier == nil
        ? UserDefaults(suiteName: appDomain) ?? .standard
        : .standard

    static var options: DetectorOptions {
        DetectorOptions(
            names: value(Key.names),
            nameHeuristics: value(Key.nameHeuristics),
            emails: value(Key.emails),
            phones: value(Key.phones),
            addresses: value(Key.addresses),
            propagate: value(Key.propagate),
            alwaysRedact: list(Key.alwaysRedact),
            neverRedact: list(Key.neverRedact)
        )
    }

    static var labels: Bool { value(Key.labels) }
    static var review: Bool { value(Key.review) }
    static var save: Bool { value(Key.save) }

    /// Unset keys fall back to the Pref's default, the same one @AppStorage uses, so no registration step is needed.
    /// Set keys go through bool(forKey:) so `defaults write … YES` (stored as a string) still counts as on.
    private static func value(_ pref: Pref<Bool>) -> Bool {
        store.object(forKey: pref.key) == nil ? pref.defaultValue : store.bool(forKey: pref.key)
    }

    private static func list(_ pref: Pref<String>) -> [String] {
        (store.string(forKey: pref.key) ?? pref.defaultValue)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// Same store as Prefs, so the Settings window edits what the detector reads even in an unbundled dev build.
extension AppStorage where Value == Bool {
    init(_ pref: Pref<Bool>) { self.init(wrappedValue: pref.defaultValue, pref.key, store: Prefs.store) }
}

extension AppStorage where Value == String {
    init(_ pref: Pref<String>) { self.init(wrappedValue: pref.defaultValue, pref.key, store: Prefs.store) }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.names) private var names: Bool
    @AppStorage(Prefs.Key.nameHeuristics) private var nameHeuristics: Bool
    @AppStorage(Prefs.Key.emails) private var emails: Bool
    @AppStorage(Prefs.Key.phones) private var phones: Bool
    @AppStorage(Prefs.Key.addresses) private var addresses: Bool
    @AppStorage(Prefs.Key.propagate) private var propagate: Bool
    @AppStorage(Prefs.Key.labels) private var labels: Bool
    @AppStorage(Prefs.Key.review) private var review: Bool
    @AppStorage(Prefs.Key.save) private var save: Bool
    @AppStorage(Prefs.Key.alwaysRedact) private var alwaysRedact: String
    @AppStorage(Prefs.Key.neverRedact) private var neverRedact: String

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
