// swift-tools-version: 6.3

import Foundation
import PackageDescription

// The probe is built against a revision of RequestDL, and what is compared is the same measurement
// against different code: `CACHE_PROBE_REV` is the directory of a checkout or of a `git archive`
// export of that revision. Without it, the probe measures the checkout it lives in.
let environment = ProcessInfo.processInfo.environment
let revision =
    environment["CACHE_PROBE_REV"]
    ?? URL(fileURLWithPath: Context.packageDirectory)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path

// SwiftPM names a path dependency after its directory.
let identity = URL(fileURLWithPath: revision).lastPathComponent

// `CACHE_PROBE_TRAITS=none` builds RequestDL without its default traits, the configuration that
// has no NIO and runs the file system calls on the portable pool.
let traits: Set<Package.Dependency.Trait> = environment["CACHE_PROBE_TRAITS"] == "none" ? [] : [.defaults]

let package = Package(
    name: "cache-probe",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: revision, traits: traits)
    ],
    targets: [
        .executableTarget(
            name: "cache-probe",
            dependencies: [
                .product(name: "RequestDL", package: identity)
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
