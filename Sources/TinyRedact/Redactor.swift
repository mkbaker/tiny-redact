import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Burns solid boxes into a brand-new bitmap. No blur (blur can be reversed) and no metadata carried over.
enum Redactor {
    static func render(_ image: CGImage, detections: [Detection], drawLabels: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for d in detections where d.enabled {
            // Detection rects are top-left origin; CGContext is bottom-left.
            let r = CGRect(x: d.rect.minX, y: CGFloat(h) - d.rect.maxY,
                           width: d.rect.width, height: d.rect.height).integral
            ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
            ctx.fill(r)
            if drawLabels, !d.label.isEmpty { drawLabel(d.label, in: r) }
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// "Person 3" → "P3" when the full label doesn't fit.
    static func shortLabel(_ label: String) -> String {
        guard let first = label.first else { return "" }
        return String(first) + label.filter(\.isNumber)
    }

    private static func drawLabel(_ label: String, in r: CGRect) {
        for text in [label, shortLabel(label)] {
            var size = min(r.height * 0.6, 28)
            while size >= 7 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
                let s = (text as NSString).size(withAttributes: attrs)
                if s.width <= r.width - 4 {
                    (text as NSString).draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                            withAttributes: attrs)
                    return
                }
                size -= 1
            }
        }
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

enum ImageLoader {
    static func load(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func load(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return load(data)
    }
}
