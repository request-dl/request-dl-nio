//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Data
#else
import struct Foundation.Data
#endif

extension Internals {

    struct ByteBufferURL: BufferURL {

        // MARK: - Internal static properties

        static var temporaryURL: Internals.ByteBufferURL {
            .init(.init())
        }

        // MARK: - Internal properties

        var writtenBytes: Int {
            url.writtenBytes
        }

        // MARK: - Private properties

        private let url: ByteURL

        // MARK: - Inits

        init(_ url: ByteURL) {
            self.url = url
        }

        // MARK: - Internal static methods

        static func make(from url: Internals.ByteURL) -> Internals.ByteBufferURL? {
            .init(url)
        }

        // MARK: - Internal methods

        func isResourceAvailable() -> Bool {
            true
        }

        func createResourceIfNeeded() {}

        func truncate() {
            url.replace(with: Data())
        }

        func absoluteURL() -> ByteURL {
            url
        }
    }
}
