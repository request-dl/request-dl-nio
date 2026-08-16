//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

private struct SomeUnderlyingError: Error {}

/// Covers `SecureFileError.init(resource:path:underlying:)`'s own classification logic --
/// relative-path detection and "can't open" vs. "invalid contents" -- independent of which
/// caller (`Certificate`, `PrivateKey`) triggered it. `Internals.Certificate`/`Internals.PrivateKey`
/// only need to get `resource`/`path`/`underlying` right; see `InternalsCertificateTests` and
/// `InternalsPrivateKeyTests` in `RequestDLInternalsTests` for that half.
struct SecureFileErrorTests {

    @Test
    func whenFileDoesNotExist_shouldReportCantOpenFileAndAbsolutePath() async throws {
        try await withTemporaryFileURL("missing.pem", createPath: false) { url in
            // Given
            let path = url.absolutePath(percentEncoded: false)

            // When
            let error = SecureFileError(resource: .certificate, path: path, underlying: SomeUnderlyingError())

            // Then
            #expect(error.resource == .certificate)
            #expect(error.path == path)
            #expect(error.isRelativePath == false)

            guard case .cantOpenFile = error.context else {
                Issue.record("Expected .cantOpenFile, got \(error.context)")
                return
            }
        }
    }

    @Test
    func whenFileContentsAreInvalid_shouldReportInvalidContents() async throws {
        try await withTemporaryFileURL("invalid.pem") { url in
            // Given
            try await url.write(Data("not a certificate".utf8))
            let path = url.absolutePath(percentEncoded: false)
            let underlying = SomeUnderlyingError()

            // When
            let error = SecureFileError(resource: .certificate, path: path, underlying: underlying)

            // Then
            #expect(error.path == path)

            guard case .invalidContents = error.context else {
                Issue.record("Expected .invalidContents, got \(error.context)")
                return
            }
        }
    }

    @Test
    func whenRelativePathDoesNotExist_shouldReportRelativePath() {
        // Given
        let path = "definitely-not-a-real-private-key.pem"

        // When
        let error = SecureFileError(resource: .privateKey, path: path, underlying: SomeUnderlyingError())

        // Then
        #expect(error.isRelativePath == true)
        #expect(error.resource == .privateKey)
    }
}
