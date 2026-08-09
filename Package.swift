// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "applevision",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AppleVisionCore",
            targets: ["AppleVisionCore"]
        ),
        .executable(
            name: "applevision",
            targets: ["applevision"]
        ),
    ],
    targets: [
        .target(
            name: "AppleVisionCore"
        ),
        .executableTarget(
            name: "applevision",
            dependencies: ["AppleVisionCore"]
        ),
        .testTarget(
            name: "AppleVisionCoreTests",
            dependencies: ["AppleVisionCore"]
        ),
    ]
)
