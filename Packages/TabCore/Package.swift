// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TabCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TabCore", targets: ["TabCore"]),
    ],
    targets: [
        .target(name: "TabCore"),
        .testTarget(
            name: "TabCoreTests",
            dependencies: ["TabCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
