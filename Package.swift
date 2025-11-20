// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "request-dl",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "RequestDL",
            targets: ["RequestDL"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-server/async-http-client",
            from: "1.30.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio",
            from: "2.90.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-extras",
            from: "1.31.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-ssl",
            from: "2.36.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-transport-services",
            from: "1.25.2"
        ),
        .package(
            url: "https://github.com/apple/swift-log",
            from: "1.6.4"
        )
    ],
    targets: [
        .target(
            name: "RequestDL",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        .testTarget(
            name: "RequestDLTests",
            dependencies: ["RequestDL"],
            resources: [.process("Resources")]
        )
    ]
)
