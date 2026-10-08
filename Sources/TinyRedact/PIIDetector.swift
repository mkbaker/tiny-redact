import Foundation
import CoreGraphics
import Vision
import NaturalLanguage

/// Everything the detector needs, snapshotted from settings so it can run off the main thread.
struct DetectorOptions {
    var names = true            // Apple's on-device named-entity tagger
    var nameHeuristics = true   // "Two or more Capitalized Words" fallback for UI text with no context
    var emails = true
    var phones = true
    var addresses = false
    var propagate = true        // once "Jane Doe" is found, also hide a bare "Jane" elsewhere
    var alwaysRedact: [String] = []
    var neverRedact: [String] = []
}

struct Detection: Identifiable {
    enum Kind: String { case name, email, phone, address, custom, manual }

    let id = UUID()
    /// Pixel rect in the source image, origin top-left.
    var rect: CGRect
    var kind: Kind
    /// The matched text. Only ever shown locally in the review window; never written to the output.
    var text: String
    var label: String = ""
    var enabled = true
}

enum PIIDetector {

    private struct Line {
        let text: String
        let candidate: VNRecognizedText
    }

    // MARK: - Public

    static func detect(in image: CGImage, options: DetectorOptions) throws -> [Detection] {
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)
        let lines = try recognizeLines(in: image)
        let never = Set(options.neverRedact.map { $0.lowercased() })
        var out: [Detection] = []

        func rect(_ line: Line, _ range: Range<String.Index>) -> CGRect? {
            guard let obs = try? line.candidate.boundingBox(for: range) else { return nil }
            let b = obs.boundingBox // normalized, origin bottom-left
            var r = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
            let pad = max(2, r.height * 0.15)
            r = r.insetBy(dx: -pad, dy: -pad).intersection(bounds)
            return (r.isNull || r.isEmpty) ? nil : r
        }

        func add(_ line: Line, _ range: Range<String.Index>, _ kind: Detection.Kind) {
            let text = String(line.text[range])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            guard !text.isEmpty, !never.contains(text.lowercased()) else { return }
            guard let r = rect(line, range) else { return }
            // Skip if an existing box already covers this one.
            if out.contains(where: { coverage(of: r, by: $0.rect) > 0.8 }) { return }
            out.append(Detection(rect: r, kind: kind, text: text))
        }

        // 1. Things you told it to always hide (customer names, company, etc.)
        for term in options.alwaysRedact where !term.isEmpty {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
            for line in lines {
                for r in ranges(of: pattern, in: line.text, options: [.caseInsensitive]) { add(line, r, .custom) }
            }
        }

        // 2. Person names via the on-device NL tagger — per line, then the whole screen as one text for context.
        if options.names {
            let tagger = NLTagger(tagSchemes: [.nameType])
            let tagOpts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

            for line in lines {
                tagger.string = line.text
                tagger.enumerateTags(in: line.text.startIndex..<line.text.endIndex, unit: .word,
                                     scheme: .nameType, options: tagOpts) { tag, range in
                    if tag == .personalName { add(line, range, .name) }
                    return true
                }
            }

            let joined = lines.map(\.text).joined(separator: "\n")
            var lineRanges: [Range<String.Index>] = []
            var cursor = joined.startIndex
            for line in lines {
                let end = joined.index(cursor, offsetBy: line.text.count)
                lineRanges.append(cursor..<end)
                cursor = end < joined.endIndex ? joined.index(after: end) : end
            }
            tagger.string = joined
            tagger.enumerateTags(in: joined.startIndex..<joined.endIndex, unit: .word,
                                 scheme: .nameType, options: tagOpts) { tag, range in
                guard tag == .personalName,
                      let i = lineRanges.firstIndex(where: { $0.contains(range.lowerBound) && range.upperBound <= $0.upperBound })
                else { return true }
                let line = lines[i]
                let lo = joined.distance(from: lineRanges[i].lowerBound, to: range.lowerBound)
                let hi = joined.distance(from: lineRanges[i].lowerBound, to: range.upperBound)
                let local = line.text.index(line.text.startIndex, offsetBy: lo)..<line.text.index(line.text.startIndex, offsetBy: hi)
                add(line, local, .name)
                return true
            }
        }

        // 3. Heuristic: runs of 2–4 Capitalized Words that aren't common UI words ("Jane Doe", "Doe, Jane").
        if options.nameHeuristics {
            for line in lines {
                let s = line.text
                var run: [Range<String.Index>] = []
                func flush() {
                    let real = run.filter { !s[$0].hasSuffix(".") } // ignore middle initials in the count
                    if (2...4).contains(real.count), let f = run.first, let l = run.last {
                        add(line, f.lowerBound..<l.upperBound, .name)
                    }
                    run.removeAll()
                }
                for w in ranges(of: capitalizedWord, in: s) {
                    if stopWords.contains(s[w].lowercased()) { flush(); continue }
                    if let last = run.last {
                        let gap = s[last.upperBound..<w.lowerBound]
                        if gap == " " || gap == "  " || gap == ", " { run.append(w); continue }
                        flush()
                    }
                    run.append(w)
                }
                flush()
            }
        }

        // 4. Emails
        if options.emails {
            let email = "[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}"
            for line in lines {
                for r in ranges(of: email, in: line.text, options: [.caseInsensitive]) { add(line, r, .email) }
            }
        }

        // 5. Phones / addresses
        var types: NSTextCheckingResult.CheckingType = []
        if options.phones { types.insert(.phoneNumber) }
        if options.addresses { types.insert(.address) }
        if !types.isEmpty, let dd = try? NSDataDetector(types: types.rawValue) {
            for line in lines {
                let s = line.text
                for m in dd.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    guard let r = Range(m.range, in: s) else { continue }
                    add(line, r, m.resultType == .phoneNumber ? .phone : .address)
                }
            }
        }

        // 6. Propagate: hide every other occurrence of any name token we found.
        if options.propagate {
            var tokens = Set<String>()
            for d in out where d.kind == .name || d.kind == .custom {
                for t in d.text.split(whereSeparator: { $0 == " " || $0 == "," }) {
                    let tok = t.trimmingCharacters(in: .punctuationCharacters)
                    guard tok.count >= 3, tok.first?.isUppercase == true,
                          !stopWords.contains(tok.lowercased()), !never.contains(tok.lowercased()) else { continue }
                    tokens.insert(tok)
                }
            }
            for tok in tokens {
                let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: tok) + "(?![\\p{L}])"
                for line in lines {
                    for r in ranges(of: pattern, in: line.text) { add(line, r, .name) }
                }
            }
        }

        assignLabels(&out)
        return out
    }

    // MARK: - OCR

    private static func recognizeLines(in image: CGImage) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            return Line(text: c.string, candidate: c)
        }
    }

    // MARK: - Labels ("Person 1", "Person 2"…) so Claude can tell people apart without knowing who they are

    static func assignLabels(_ dets: inout [Detection]) {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" })
                .map(String.init)
                .filter { $0.count >= 2 })
        }
        var people: [Set<String>] = []
        // Longest names first so "Jane" attaches to "Jane Doe".
        let order = dets.indices.sorted { tokens(dets[$0].text).count > tokens(dets[$1].text).count }
        for i in order {
            switch dets[i].kind {
            case .name:
                let t = tokens(dets[i].text)
                if let idx = people.firstIndex(where: { !t.isEmpty && t.isSubset(of: $0) }) {
                    dets[i].label = "Person \(idx + 1)"
                } else {
                    people.append(t)
                    dets[i].label = "Person \(people.count)"
                }
            case .email:   dets[i].label = "Email"
            case .phone:   dets[i].label = "Phone"
            case .address: dets[i].label = "Address"
            case .custom, .manual: dets[i].label = "Redacted"
            }
        }
    }

    // MARK: - Helpers

    static func coverage(of a: CGRect, by b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        let area = a.width * a.height
        guard !i.isNull, area > 0 else { return 0 }
        return (i.width * i.height) / area
    }

    private static func ranges(of pattern: String, in s: String,
                               options: NSRegularExpression.Options = []) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s) }
    }

    /// A capitalized word containing at least one lowercase letter (skips ALL-CAPS headers), or a middle initial "J."
    private static let capitalizedWord =
        "(?<![\\p{L}])(?:\\p{Lu}[\\p{L}'’\\-]*\\p{Ll}[\\p{L}'’\\-]*|\\p{Lu}\\.)(?![\\p{L}])"

    /// Common UI / business words that break a "name run". Add your app's own labels via "Never redact".
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "for", "to", "with", "on", "at", "by", "from", "in", "out", "my", "your",
        "settings", "account", "profile", "sign", "log", "home", "dashboard", "search", "help", "support", "contact",
        "new", "edit", "delete", "save", "cancel", "submit", "view", "all", "more", "details", "open", "close", "closed",
        "status", "active", "inactive", "pending", "total", "first", "last", "name", "email", "phone", "address",
        "date", "time", "today", "yesterday", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "january", "february", "march", "july", "august", "september",
        "october", "november", "december", "user", "users", "admin", "team", "teams", "project", "projects", "report",
        "reports", "note", "notes", "message", "messages", "inbox", "sent", "draft", "drafts", "order", "orders",
        "invoice", "invoices", "customer", "customers", "client", "clients", "billing", "payment", "payments",
        "privacy", "policy", "terms", "service", "services", "add", "remove", "update", "create", "download", "upload",
        "export", "import", "share", "filter", "sort", "show", "hide", "back", "next", "previous", "page", "welcome",
        "hello", "hi", "dear", "thanks", "thank", "you", "overview", "summary", "general", "members", "member", "owner",
        "role", "roles", "group", "groups", "company", "organization", "department", "manager", "director",
        "assigned", "assignee", "created", "updated", "modified", "due", "priority", "high", "low", "medium",
        "resolved", "ticket", "tickets", "issue", "issues", "task", "tasks", "calendar", "event", "events", "file",
        "files", "folder", "document", "documents", "upgrade", "plan", "free", "pro", "premium", "learn", "get",
        "started", "read", "unread", "mark", "reply", "forward", "archive", "notifications", "preferences",
        "security", "password", "language", "theme", "dark", "light", "mode", "street", "avenue", "road", "city",
        "state", "united", "states", "north", "south", "east", "west", "google", "apple", "microsoft", "amazon",
        "chrome", "safari", "windows", "claude", "id", "type", "amount", "balance", "description", "category",
        "actions", "action", "copy", "paste", "undo", "redo", "window", "tools", "insert", "format",
    ]
}
