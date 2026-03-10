// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PosterStudio",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PosterStudio", targets: ["PosterStudio"]),
    ],
    targets: [
        .executableTarget(
            name: "PosterStudio",
            path: "Sources/PosterStudio"
        ),
    ]
)
