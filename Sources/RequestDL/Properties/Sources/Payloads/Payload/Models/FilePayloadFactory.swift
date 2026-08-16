//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

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
        try await validateFileExists()

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

    // MARK: - Private methods

    /// Confirms `url` can actually be read before handing it to `Internals.FileBuffer`, which
    /// silently treats a missing or unreadable file as an empty one — see `Internals.Buffer`.
    private func validateFileExists() async throws {
        do {
            guard try await Internals.fileSystem.info(forFileAt: url.filePath) != nil else {
                throw FilePayloadError(url: url, context: .notFound)
            }
        } catch let error as FilePayloadError {
            throw error
        } catch {
            throw FilePayloadError(url: url, context: .cantAccessFile(reason: error))
        }
    }
}
