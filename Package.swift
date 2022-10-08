// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RequestDL",
    platforms: [.iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macOS(.v11)],
    products: [
        .library(
            name: "RequestDL",
            targets: ["RequestDL"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "RequestDL",
            dependencies: []
        ),
        .testTarget(
            name: "RequestDLTests",
            dependencies: ["RequestDL"]
        )
    ]
)
