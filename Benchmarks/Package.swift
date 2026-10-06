// swift-tools-version: 6.2

import Foundation
import PackageDescription

// The fork is pinned to one exact version per build, because what is compared is the same client
// code against two versions of it: `BENCH_AHC_VERSION=1.38.2 swift build ...`, then the same with
// `1.39.1`. `run.sh` does both. This package does not depend on RequestDL: it needs the fork
// `from: "1.39.1"`, which could not be pinned to an older one here.
let ahcVersion = ProcessInfo.processInfo.environment["BENCH_AHC_VERSION"] ?? "1.39.1"

let package = Package(
    name: "benchmarks",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/request-dl/async-http-client",
            exact: Version(stringLiteral: ahcVersion)
        ),
        .package(
            url: "https://github.com/apple/swift-nio",
            from: "2.103.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "bench-server",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "bench-client",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
    ],
    // Two small executables, written for the numbers they print and not as a library: the Swift 5
    // mode keeps the top-level code of each from needing isolation it has no use for.
    swiftLanguageModes: [.v5]
)
