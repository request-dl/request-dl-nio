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
        try await validateFileExists()

        return await .init(
            contentType: contentType,
            source: .buffer(Internals.FileBuffer(url))
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
