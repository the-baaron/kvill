// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kvill",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kvill",
            path: "Sources/Kvill"
        )
    ]
)
