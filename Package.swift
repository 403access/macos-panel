// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacosPanel",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MacosPanel",
            path: "Sources/MacosPanel"
        )
    ]
)
