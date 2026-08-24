// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AtollCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AtollCore", targets: ["AtollCore"])
    ],
    targets: [
        .target(
            name: "AtollCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AtollCoreTests",
            dependencies: ["AtollCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
