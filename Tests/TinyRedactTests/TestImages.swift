import AppKit
import CoreGraphics

/// Builds synthetic images for tests and reads pixels back. All points and rects are top-left origin,
/// matching `Detection.rect`.
enum TestImages {
    struct RGBA: Equatable {
        var r, g, b, a: UInt8
    }

    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)

    static func solid(width: Int, height: Int, color: RGBA) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                                 blue: CGFloat(color.b) / 255, alpha: CGFloat(color.a) / 255))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Black text on white, one line per entry, each line 60 px tall.
    /// Returns the image and a function that gives the rect of a substring of a line.
    static func text(_ lines: [String], fontSize: CGFloat = 28)
        -> (image: CGImage, rectOf: (_ substring: String, _ line: Int) -> CGRect) {
        let width = 1400, lineHeight: CGFloat = 60, margin: CGFloat = 20
        let height = Int(lineHeight) * lines.count + 40
        let ctx = context(width: width, height: height)
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize),
                                                    .foregroundColor: NSColor.black]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, line) in lines.enumerated() {
            // Bottom-left origin while drawing.
            (line as NSString).draw(at: CGPoint(x: margin, y: CGFloat(height) - lineHeight * CGFloat(i + 1)),
                                    withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        let rectOf = { (substring: String, i: Int) -> CGRect in
            let line = lines[i] as NSString
            let r = line.range(of: substring)
            precondition(r.location != NSNotFound, "\(substring) not in \(line)")
            let x = margin + (line.substring(to: r.location) as NSString).size(withAttributes: attrs).width
            let size = (substring as NSString).size(withAttributes: attrs)
            let top = lineHeight * CGFloat(i + 1) - size.height
            return CGRect(x: x, y: top, width: size.width, height: size.height)
        }
        return (ctx.makeImage()!, rectOf)
    }

    /// The pixel at a top-left-origin point, converted to 8-bit sRGB.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Bitmap memory is stored top row first.
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self) + y * ctx.bytesPerRow + x * 4
        return RGBA(r: p[0], g: p[1], b: p[2], a: p[3])
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
