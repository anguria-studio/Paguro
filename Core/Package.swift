// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaguroCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "PaguroCore", targets: ["PaguroCore"])
    ],
    targets: [
        .target(
            name: "PaguroCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PaguroCoreTests",
            dependencies: ["PaguroCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
