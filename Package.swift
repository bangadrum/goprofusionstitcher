// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoProFusionStitcher",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GoProFusionStitcher",
            path: "Sources/GoProFusionStitcher"
        )
    ]
)
