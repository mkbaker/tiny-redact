import Foundation

/// `TinyRedact --redact in.png out.png` — runs detection with your saved settings and writes the result.
/// Handy for checking what gets caught on a sample screenshot without the UI.
enum CLI {
    static func run(input: String, output: String) -> Int32 {
        guard let image = ImageLoader.load(URL(fileURLWithPath: input)) else {
            FileHandle.standardError.write("Couldn't read \(input)\n".data(using: .utf8)!)
            return 1
        }
        do {
            let detections = try PIIDetector.detect(in: image, options: Prefs.options)
            for d in detections {
                let r = d.rect.integral
                print("\(d.label)\t\(d.kind.rawValue)\t\(d.text)\t\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
            }
            guard let out = Redactor.render(image, detections: detections, drawLabels: Prefs.labels),
                  let png = Redactor.png(out) else { return 1 }
            try png.write(to: URL(fileURLWithPath: output))
            print("\(detections.count) redactions → \(output)")
            return 0
        } catch {
            FileHandle.standardError.write("Error: \(error.localizedDescription)\n".data(using: .utf8)!)
            return 1
        }
    }
}
