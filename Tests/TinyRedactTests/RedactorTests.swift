import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import TinyRedact

final class RedactorTests: XCTestCase {
    private func isFill(_ p: TestImages.RGBA) -> Bool {
        // Opaque dark gray: the box colour, with nothing of the red underneath showing through.
        p.a == 255 && p.r == p.g && p.g == p.b && p.r < 60
    }

    func testEnabledBoxIsFilledAndDisabledBoxIsUntouched() throws {
        let image = TestImages.solid(width: 100, height: 100, color: TestImages.red)
        let enabled = Detection(rect: CGRect(x: 10, y: 10, width: 30, height: 20), kind: .name, text: "Jane")
        var disabled = Detection(rect: CGRect(x: 60, y: 60, width: 30, height: 20), kind: .name, text: "John")
        disabled.enabled = false

        let out = try XCTUnwrap(Redactor.render(image, detections: [enabled, disabled], drawLabels: false))

        for (x, y) in [(10, 10), (25, 20), (39, 29)] {
            XCTAssertTrue(isFill(TestImages.pixel(out, x: x, y: y)), "inside enabled box at \(x),\(y)")
        }
        XCTAssertEqual(TestImages.pixel(out, x: 75, y: 70), TestImages.red, "inside disabled box")
        XCTAssertEqual(TestImages.pixel(out, x: 50, y: 50), TestImages.red, "outside every box")
    }

    func testRectsAreTopLeftOrigin() throws {
        let image = TestImages.solid(width: 100, height: 100, color: TestImages.red)
        let top = Detection(rect: CGRect(x: 0, y: 0, width: 100, height: 20), kind: .manual, text: "")

        let out = try XCTUnwrap(Redactor.render(image, detections: [top], drawLabels: false))

        XCTAssertTrue(isFill(TestImages.pixel(out, x: 50, y: 5)), "top strip is filled")
        XCTAssertEqual(TestImages.pixel(out, x: 50, y: 95), TestImages.red, "bottom strip is untouched")
    }

    func testLabelDoesNotRevealWhatIsUnderneath() throws {
        let image = TestImages.solid(width: 200, height: 100, color: TestImages.red)
        var d = Detection(rect: CGRect(x: 20, y: 20, width: 160, height: 60), kind: .name, text: "Jane Doe")
        d.label = "Person 1"

        let out = try XCTUnwrap(Redactor.render(image, detections: [d], drawLabels: true))

        // White label text is drawn somewhere in the box, but no red shows through anywhere inside it.
        var sawLabel = false
        for y in stride(from: 20, to: 80, by: 2) {
            for x in stride(from: 20, to: 180, by: 2) {
                let p = TestImages.pixel(out, x: x, y: y)
                XCTAssertFalse(p.r > 200 && p.g < 50, "red leaked at \(x),\(y)")
                if p.r > 200 && p.g > 200 { sawLabel = true }
            }
        }
        XCTAssertTrue(sawLabel)
    }

    func testPNGCarriesNoSourceMetadata() throws {
        // A source PNG with EXIF and GPS data, as a photo or a screenshot tool might write.
        let source = TestImages.solid(width: 40, height: 40, color: TestImages.red)
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Jane Doe's laptop"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"],
        ]
        CGImageDestinationAddImage(dest, source, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let loaded = try XCTUnwrap(ImageLoader.load(data as Data))

        let out = try XCTUnwrap(Redactor.render(loaded, detections: [], drawLabels: false))
        let png = try XCTUnwrap(Redactor.png(out))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let outProps = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        // ImageIO writes its own minimal Exif block (colour space, size); nothing from the source may survive.
        let exif = outProps[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifUserComment])
        XCTAssertNil(outProps[kCGImagePropertyGPSDictionary])
    }

    func testShortLabel() {
        XCTAssertEqual(Redactor.shortLabel("Person 12"), "P12")
        XCTAssertEqual(Redactor.shortLabel("Email"), "E")
        XCTAssertEqual(Redactor.shortLabel(""), "")
    }
}
