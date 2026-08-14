// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Foldout",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Foldout",
            path: "Sources/Foldout"
        )
    ]
)
