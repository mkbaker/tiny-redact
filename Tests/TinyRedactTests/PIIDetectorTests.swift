import XCTest
import CoreGraphics
@testable import TinyRedact

final class PIIDetectorTests: XCTestCase {

    // MARK: - Labels

    func testSamePersonKeepsTheSameLabel() {
        var dets = [
            Detection(rect: .zero, kind: .name, text: "Jane"),
            Detection(rect: .zero, kind: .name, text: "Jane Doe"),
            Detection(rect: .zero, kind: .name, text: "John Smith"),
            Detection(rect: .zero, kind: .name, text: "Smith"),
            Detection(rect: .zero, kind: .email, text: "jane@example.com"),
            Detection(rect: .zero, kind: .phone, text: "555-0100"),
            Detection(rect: .zero, kind: .custom, text: "Acme"),
            Detection(rect: .zero, kind: .manual, text: ""),
        ]
        PIIDetector.assignLabels(&dets)

        XCTAssertEqual(dets[0].label, dets[1].label, "Jane joins Jane Doe")
        XCTAssertEqual(dets[2].label, dets[3].label, "Smith joins John Smith")
        XCTAssertNotEqual(dets[1].label, dets[2].label)
        XCTAssertEqual(Set([dets[1].label, dets[2].label]), ["Person 1", "Person 2"])
        XCTAssertEqual(dets[4].label, "Email")
        XCTAssertEqual(dets[5].label, "Phone")
        XCTAssertEqual(dets[6].label, "Redacted")
        XCTAssertEqual(dets[7].label, "Redacted")
    }

    // MARK: - Capitalized-name heuristic

    private func runs(_ s: String) -> [String] {
        PIIDetector.nameRuns(in: s).map { String(s[$0]) }
    }

    func testNameRuns() {
        XCTAssertEqual(runs("Jane Doe"), ["Jane Doe"])
        XCTAssertEqual(runs("Mary J. Smith"), ["Mary J. Smith"])
        XCTAssertEqual(runs("Doe, Jane"), ["Doe, Jane"])
        XCTAssertEqual(runs("Doe, Jane M."), ["Doe, Jane M."])
        XCTAssertEqual(runs("Assigned to Jane Doe"), ["Jane Doe"], "stop words break the run")
        XCTAssertEqual(runs("Jane"), [], "one word alone is too weak a signal")
        XCTAssertEqual(runs("ORDER STATUS"), [], "all-caps headers are skipped")
    }

    /// #6: a comma-separated list must not be dropped (too many words) or merged into one person.
    func testCommaSeparatedListSplitsIntoPeople() {
        XCTAssertEqual(runs("Jane Doe, John Smith, Bob Lee"), ["Jane Doe", "John Smith", "Bob Lee"])
        XCTAssertEqual(runs("Jane Doe, John Smith"), ["Jane Doe", "John Smith"])
        XCTAssertEqual(runs("CC: Mary J. Smith, Bob Lee"), ["Mary J. Smith", "Bob Lee"])
        XCTAssertEqual(runs("Jane Doe, John Smith (owner)"), ["Jane Doe", "John Smith"])
        XCTAssertEqual(runs("Jane Doe, John Smith, Bob"), ["Jane Doe", "John Smith", "Bob"])
        XCTAssertEqual(runs("Jane Doe, John, Bob Lee, Ann"), ["Jane Doe", "John", "Bob Lee", "Ann"])
    }

    func testSplitListGetsSeparateLabels() {
        let s = "Jane Doe, John Smith"
        var dets = PIIDetector.nameRuns(in: s).map { Detection(rect: .zero, kind: .name, text: String(s[$0])) }
        dets.append(Detection(rect: .zero, kind: .name, text: "Smith"))
        PIIDetector.assignLabels(&dets)

        XCTAssertNotEqual(dets[0].label, dets[1].label)
        XCTAssertEqual(dets[2].label, dets[1].label, "Smith is John Smith, not Jane Doe")
    }

    // MARK: - Propagation

    /// #9: parts of an Always-redact term are hidden elsewhere too, but not labelled as a person.
    func testPropagatedTokensKeepTheirSourceKind() {
        let dets = [
            Detection(rect: .zero, kind: .custom, text: "Acme Corp"),
            Detection(rect: .zero, kind: .name, text: "Jane Doe"),
            Detection(rect: .zero, kind: .custom, text: "Jane Industries"),
            Detection(rect: .zero, kind: .email, text: "Bob@example.com"),
        ]
        let tokens = PIIDetector.propagationTokens(from: dets, never: ["industries"])

        XCTAssertEqual(tokens, ["Acme": .custom, "Corp": .custom, "Jane": .name, "Doe": .name])
    }

    func testPropagatedCustomTermIsLabelledRedacted() throws {
        var options = DetectorOptions()
        options.alwaysRedact = ["Acme Corp"]
        let (image, rectOf) = TestImages.text(["Contact Acme Corp or Acme support"])
        let dets = try PIIDetector.detect(in: image, options: options)

        let bare = rectOf("Acme support", 0)
        let hit = try XCTUnwrap(dets.first { $0.rect.contains(CGPoint(x: bare.minX + 10, y: bare.midY)) },
                                "bare Acme is not covered")
        XCTAssertEqual(hit.label, "Redacted")
        XCTAssertFalse(dets.contains { $0.label.hasPrefix("Person") }, "\(dets.map { ($0.text, $0.label) })")
    }

    // MARK: - Overlapping boxes (#1)

    func testNearDuplicateGrowsTheExistingBox() {
        var out = [Detection(rect: CGRect(x: 0, y: 0, width: 87, height: 10), kind: .name,
                             text: "Christopher Alexander")]
        PIIDetector.merge(Detection(rect: CGRect(x: 0, y: 0, width: 100, height: 10), kind: .name,
                                    text: "Christopher Alexander Wu"), into: &out)

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].rect, CGRect(x: 0, y: 0, width: 100, height: 10))
        XCTAssertEqual(out[0].text, "Christopher Alexander Wu")
    }

    func testContainedBoxIsDropped() {
        let big = CGRect(x: 0, y: 0, width: 100, height: 10)
        var out = [Detection(rect: big, kind: .name, text: "Jane Doe")]
        PIIDetector.merge(Detection(rect: CGRect(x: 0, y: 0, width: 40, height: 10), kind: .name, text: "Jane"),
                          into: &out)

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].rect, big)
        XCTAssertEqual(out[0].text, "Jane Doe")
    }

    func testSeparateBoxIsKept() {
        var out = [Detection(rect: CGRect(x: 0, y: 0, width: 50, height: 10), kind: .name, text: "Jane")]
        PIIDetector.merge(Detection(rect: CGRect(x: 60, y: 0, width: 50, height: 10), kind: .name, text: "Doe"),
                          into: &out)
        XCTAssertEqual(out.count, 2)
    }

    // MARK: - End to end (Vision + NaturalLanguage)

    /// The full box covers every word of the name, not just the part the first pass found.
    func testShortTrailingSurnameIsCovered() throws {
        let lines = ["Assigned to Christopher Alexander Wu yesterday",
                     "Owner: Bartholomew Montgomery Ng"]
        let (image, rectOf) = TestImages.text(lines)
        let dets = try PIIDetector.detect(in: image, options: DetectorOptions())

        for (word, line) in [("Christopher", 0), ("Wu", 0), ("Bartholomew", 1), ("Ng", 1)] {
            let r = rectOf(word, line)
            let center = CGPoint(x: r.midX, y: r.midY)
            XCTAssertTrue(dets.contains { $0.enabled && $0.rect.contains(center) }, "\(word) is not covered")
        }
        XCTAssertFalse(dets.contains { $0.rect.contains(CGPoint(x: rectOf("yesterday", 0).midX,
                                                                y: rectOf("yesterday", 0).midY)) })
    }

    func testCapitalizedNameFallbackFindsTableCells() throws {
        // No sentence context, so this relies on the capitalized-run heuristic.
        var options = DetectorOptions()
        options.names = false
        let (image, rectOf) = TestImages.text(["Doe, Jane", "Mary J. Smith"])
        let dets = try PIIDetector.detect(in: image, options: options)

        for (word, line) in [("Doe", 0), ("Jane", 0), ("Mary", 1), ("Smith", 1)] {
            let r = rectOf(word, line)
            XCTAssertTrue(dets.contains { $0.rect.contains(CGPoint(x: r.midX, y: r.midY)) }, "\(word) is not covered")
        }
    }

    func testNeverRedactWins() throws {
        // A product name the heuristic mistakes for a person…
        let (image, _) = TestImages.text(["Acme Widgets"])
        XCTAssertFalse(try PIIDetector.detect(in: image, options: DetectorOptions()).isEmpty)

        // …until it's on the Never list.
        var options = DetectorOptions()
        options.neverRedact = ["Acme Widgets"]
        let dets = try PIIDetector.detect(in: image, options: options)
        XCTAssertTrue(dets.isEmpty, "\(dets.map(\.text))")
    }

    /// The app relies on this throwing (not returning []) to avoid shipping an unscanned image (#2).
    func testTinyImageThrows() {
        let image = TestImages.solid(width: 2, height: 2, color: TestImages.red)
        XCTAssertThrowsError(try PIIDetector.detect(in: image, options: DetectorOptions()))
    }
}
