//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct DataPayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let data: Data
    let contentType: ContentType

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        await .init(
            contentType: contentType,
            source: .buffer(Internals.DataBuffer(data))
        )
    }
}
