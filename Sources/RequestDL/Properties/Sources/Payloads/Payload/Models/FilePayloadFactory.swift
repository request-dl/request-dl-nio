//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

struct FilePayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let url: URL
    let contentType: ContentType

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        await .init(
            contentType: contentType,
            source: .buffer(Internals.FileBuffer(url))
        )
    }
}
