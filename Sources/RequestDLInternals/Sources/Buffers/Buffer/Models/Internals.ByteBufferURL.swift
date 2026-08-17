//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    /// Addresses an in memory ``Internals/ByteURL``.
    package struct ByteBufferURL: BufferURL {

        // MARK: - Internal static properties

        /// A fresh, empty store. Nothing to clean up afterwards: ARC handles it.
        package static var temporaryURL: Internals.ByteBufferURL {
            .init(.init())
        }

        // MARK: - Internal properties

        /// - Note: `async` for the protocol only. Reading this never suspends.
        package var writtenBytes: Int {
            get async {
                url.writtenBytes
            }
        }

        // MARK: - Private properties

        private let url: ByteURL

        // MARK: - Inits

        package init(_ url: ByteURL) {
            self.url = url
        }

        // MARK: - Internal static methods

        package static func make(from url: Internals.ByteURL) -> Internals.ByteBufferURL? {
            .init(url)
        }

        // MARK: - Internal methods

        /// Always. The store exists for as long as this value does.
        package func isResourceAvailable() async -> Bool {
            true
        }

        package func createResourceIfNeeded() async {}

        package func truncate() async {
            url.replace(with: Data())
        }

        package func absoluteURL() -> ByteURL {
            url
        }
    }
}
