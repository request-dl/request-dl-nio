// swift-tools-version: 5.7
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
            from: "1.19.0"
        ),
        .package(
            url: "https://github.com/apple/swift-docc-plugin.git",
            from: "1.3.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio.git",
            from: "2.58.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-extras.git",
            from: "1.19.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-ssl.git",
            from: "2.25.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.5.3"
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
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        .testTarget(
            name: "RequestDLTests",
            dependencies: [
                "RequestDL",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log")
            ],
            resources: [.process("Resources")]
        )
    ]
)
