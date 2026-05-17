// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoamCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RoamCore", targets: ["RoamCore"]),
    ],
    targets: [
        .target(name: "RoamCore"),
        .testTarget(
            name: "RoamCoreTests",
            dependencies: ["RoamCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
