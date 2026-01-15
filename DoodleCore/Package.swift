// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DoodleCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DoodleCore",
            targets: ["DoodleCore"]
        )
    ],
    targets: [
        .target(
            name: "DoodleCore"
        ),
        .testTarget(
            name: "DoodleCoreTests",
            dependencies: ["DoodleCore"]
        )
    ]
)
