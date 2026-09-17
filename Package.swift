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
    traits: [
        .trait(
            name: "NIOTransport",
            description: """
                Pulls in AsyncHTTPClient/SwiftNIO/NIOSSL, backing the .nio/.nioTransportServices \
                executors plus the NIOFileSystem-based disk I/O and the built-in gzip/deflate \
                request compression. Disabling it (`--disable-default-traits`) drops that whole \
                dependency subgraph from the build and leaves RequestDL running .urlSession-only, \
                over the portable mirrors every `#if canImport(NIOCore)` gate in this package \
                falls back to. Darwin only: `Internals.URLSessionClient` (the whole `.urlSession` \
                executor implementation) is itself Darwin-exclusive, a pre-existing decision \
                unrelated to this trait, so disabling `NIOTransport` on any other platform leaves \
                no executor at all and the package won't build.
                """
        ),
        .default(enabledTraits: ["NIOTransport"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/request-dl/async-http-client",
            from: "1.38.1"
        ),
        .package(
            url: "https://github.com/apple/swift-nio",
            from: "2.102.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-extras",
            from: "1.35.1"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-ssl",
            from: "2.37.4"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-transport-services",
            from: "1.28.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log",
            from: "1.15.0"
        ),
        .package(
            url: "https://github.com/apple/swift-collections",
            from: "1.6.0"
        ),
        .package(
            url: "https://github.com/o-nnerb/swift-async-stream",
            from: "2.1.4"
        ),
        .package(
            url: "https://github.com/apple/swift-async-algorithms",
            from: "1.1.5"
        ),
        .package(
            url: "https://github.com/apple/swift-system",
            from: "1.8.1"
        ),
        .package(
            url: "https://github.com/apple/swift-distributed-tracing",
            from: "1.4.1"
        ),
        .package(
            url: "https://github.com/apple/swift-configuration",
            from: "1.2.0",
            traits: []
        ),
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "4.5.2"
        ),
        .package(
            url: "https://github.com/apple/swift-certificates.git",
            from: "1.20.0"
        ),
    ],
    targets: [
        .target(
            name: "RequestDLInternals",
            dependencies: [
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "SwiftAsyncStream", package: "swift-async-stream"),
                .product(name: "NIO", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOConcurrencyHelpers",
                    package: "swift-nio",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(
                    name: "NIOFoundationEssentialsCompat",
                    package: "swift-nio",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "NIOEmbedded", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "_NIOFileSystem", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOHTTPCompression",
                    package: "swift-nio-extras",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOTransportServices",
                    package: "swift-nio-transport-services",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            swiftSettings: [.defaultIsolation(nil)],
        ),

        .target(
            name: "RequestDL",
            dependencies: [
                "RequestDLInternals",
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "SwiftAsyncStream", package: "swift-async-stream"),
                .product(name: "NIO", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOConcurrencyHelpers",
                    package: "swift-nio",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(
                    name: "NIOFoundationEssentialsCompat",
                    package: "swift-nio",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "_NIOFileSystem", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOHTTPCompression",
                    package: "swift-nio-extras",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOTransportServices",
                    package: "swift-nio-transport-services",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
            swiftSettings: [.defaultIsolation(nil)],
        ),

        .target(
            name: "RequestDLTestSupport",
            dependencies: [
                "RequestDLInternals",
                "RequestDL",
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "SwiftAsyncStream", package: "swift-async-stream"),
                .product(name: "NIO", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOConcurrencyHelpers",
                    package: "swift-nio",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(traits: ["NIOTransport"])),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(traits: ["NIOTransport"])),
                .product(
                    name: "NIOTransportServices",
                    package: "swift-nio-transport-services",
                    condition: .when(traits: ["NIOTransport"])
                ),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Tests/RequestDLTestSupport",
            swiftSettings: [.defaultIsolation(nil)],
        ),

        .testTarget(
            name: "RequestDLTests",
            dependencies: [
                "RequestDL",
                "RequestDLInternals",
                "RequestDLTestSupport",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "SwiftAsyncTesting", package: "swift-async-stream"),
            ],
            resources: [.process("Resources")]
        ),

        .testTarget(
            name: "RequestDLInternalsTests",
            dependencies: [
                "RequestDLInternals",
                "RequestDLTestSupport",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftAsyncTesting", package: "swift-async-stream"),
            ],
            path: "Tests/RequestDLInternalsTests",
            resources: [.process("Resources")]
        ),
    ]
)
