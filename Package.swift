// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WWQOA",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "WWQOA", targets: ["WWQOA"]),
    ],
    dependencies: [
        .package(url: "https://github.com/William-Weng/WWByteReader", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/William-Weng/WWWavWriter", .upToNextMinor(from: "1.1.0")),
    ],
    targets: [
        .target(
            name: "WWQOA",
            dependencies: [
                .product(name: "WWByteReader", package: "WWByteReader"),
                .product(name: "WWWavWriter", package: "WWWavWriter"),
            ],
            resources: [.copy("Privacy")]
        ),
    ],
    swiftLanguageVersions: [
        .v5
    ]
)
