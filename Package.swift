// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TinyRedact",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TinyRedact",
            path: "Sources/TinyRedact"
        )
    ]
)
