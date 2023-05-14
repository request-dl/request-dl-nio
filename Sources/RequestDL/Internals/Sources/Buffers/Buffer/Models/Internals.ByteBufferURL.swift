/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

        // MARK: - Internal methods

        func isResourceAvailable() -> Bool {
            true
        }

        func createResourceIfNeeded() {}

        func absoluteURL() -> ByteURL {
            url
        }
    }
}
