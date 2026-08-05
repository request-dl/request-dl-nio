//
// See LICENSE for this package's licensing information.
//

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// The checked-in `Resources` directory, located relative to this source file rather than
/// through `Bundle.module` — the resource bundle machinery needs `Foundation`, which is not
/// part of `FoundationEssentials`.
///
/// Anchored on the `RequestDLTests` path component rather than a fixed number of
/// `deletingLastPathComponent()` calls, so a fixture consumer moving to a different
/// subdirectory does not silently point at the wrong place.
let testResourcesDirectory: URL = {
    let components = #filePath.split(separator: "/")

    guard let testsRootIndex = components.firstIndex(of: "RequestDLTests") else {
        preconditionFailure("Expected '\(#filePath)' to live under a 'RequestDLTests' directory")
    }

    let testsRootPath = "/" + components[0...testsRootIndex].joined(separator: "/")
    return URL(fileURLWithPath: testsRootPath, isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
}()

struct ResourceFile {

    let resource: String

    init(_ resource: String) {
        self.resource = resource
    }

    func data() async throws -> Data {
        try await url().readData()
    }

    func url() async throws -> URL {
        let url = testResourcesDirectory.appendingPathComponent(resource)

        guard await url.isReachable else {
            throw FileNotFoundError()
        }

        return url
    }
}

struct FileNotFoundError: Error {}
