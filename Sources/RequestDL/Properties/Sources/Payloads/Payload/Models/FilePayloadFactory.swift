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
    let offset: UInt64

    // MARK: - Inits

    init(
        url: URL,
        contentType: ContentType,
        offset: UInt64 = .zero
    ) {
        self.url = url
        self.contentType = contentType
        self.offset = offset
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        var buffer = await Internals.FileBuffer(url)

        if offset > .zero {
            let availableBytes = buffer.writerIndex

            guard offset <= UInt64(availableBytes) else {
                throw InvalidPayloadOffsetError(
                    offset: offset,
                    availableBytes: availableBytes
                )
            }

            buffer.moveReaderIndex(to: Int(offset))
        }

        return .init(
            contentType: contentType,
            source: .buffer(buffer)
        )
    }
}
