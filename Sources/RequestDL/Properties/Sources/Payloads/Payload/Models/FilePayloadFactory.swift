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

    /// Refuses a file that cannot be counted in an `Int`: its body would be sent empty, with a
    /// length of zero, since nothing past what an `Int` holds can be addressed.
    ///
    /// - Parameter limit: The largest size that is representable; only a test sets it, to stand in
    ///   for a 32-bit `Int` without a file of 2 GiB.
    static func validate(size: Int64, of url: URL, limit: Int = .max) throws {
        guard size <= Int64(limit) else {
            throw FilePayloadError(url: url, context: .tooLarge(size: size))
        }
    }

    /// Confirms `url` can actually be read before handing it to `Internals.FileBuffer`, which
    /// silently treats a missing or unreadable file as an empty one (see `Internals.Buffer`).
    private func validateFileExists() async throws {
        do {
            guard let info = try await Internals.fileSystem.info(forFileAt: url.filePath) else {
                throw FilePayloadError(url: url, context: .notFound)
            }

            try Self.validate(size: info.size, of: url)
        } catch let error as FilePayloadError {
            throw error
        } catch {
            throw FilePayloadError(url: url, context: .cantAccessFile(reason: error))
        }
    }
}
