// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "request-dl",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
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
            from: "1.30.2"
        ),
        .package(
            url: "https://github.com/apple/swift-nio",
            from: "2.101.3"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-extras",
            from: "1.34.3"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-ssl",
            from: "2.37.2"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-transport-services",
            from: "1.26.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log",
            from: "1.14.0"
        ),
        .package(
            url: "https://github.com/apple/swift-collections",
            from: "1.6.0"
        ),
        .package(
            url: "https://github.com/o-nnerb/swift-async-stream",
            from: "2.0.1"
        ),
        .package(
            url: "https://github.com/apple/swift-async-algorithms",
            from: "1.1.5"
        ),
    ],
    targets: [
        .target(
            name: "RequestDL",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "SwiftAsyncStream", package: "swift-async-stream"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "NIOHTTPCompression", package: "swift-nio-extras"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),

        .testTarget(
            name: "RequestDLTests",
            dependencies: [
                "RequestDL",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            resources: [.process("Resources")]
        ),
    ]
)
