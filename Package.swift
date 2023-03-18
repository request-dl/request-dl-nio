// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RequestDL",
    platforms: [.iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macOS(.v11)],
    products: [
//        .library(
//            name: "RequestDL",
//            targets: ["RequestDL"]
//        ),
        .library(
            name: "RequestDLInternals",
            targets: ["RequestDLInternals"]
        )
    ],
    dependencies: [
        /* DocC
         .package(
             url: "https://github.com/apple/swift-docc-plugin.git",
             from: "1.0.0"
         ),
         DocC */
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),

        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.22.0"),
        
        .package(
            url: "https://github.com/swift-server/async-http-client",
            from: "1.15.0"
        )
    ],
    targets: [
        .target(
            name: "RequestDLInternals",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ]
        ),

        .testTarget(
            name: "RequestDLInternalsTests",
            dependencies: ["RequestDLInternals"]
        )

//        .target(
//            name: "RequestDL",
//            dependencies: ["RequestDLInternals"]
//        ),
//        .testTarget(
//            name: "RequestDLTests",
//            dependencies: ["RequestDL"],
//            resources: [.process("Resources")]
//        )
    ]
)
