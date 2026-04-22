// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WWQOA",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "WWQOA", targets: ["WWQOA"]),
    ],
    targets: [
        .target(name: "WWQOA"),
    ],
    swiftLanguageVersions: [
        .v5
    ]
)
