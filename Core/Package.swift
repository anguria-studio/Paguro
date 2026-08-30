// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlattaCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "BlattaCore", targets: ["BlattaCore"])
    ],
    targets: [
        .target(
            name: "BlattaCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BlattaCoreTests",
            dependencies: ["BlattaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
