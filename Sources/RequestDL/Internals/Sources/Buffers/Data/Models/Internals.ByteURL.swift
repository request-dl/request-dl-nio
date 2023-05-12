/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    final class ByteURL {

        lazy var buffer = NIOCore.ByteBuffer()
        var writtenBytes: Int = .zero

        init() {}

        /// This should only be used to wraps a ByteBuffer that
        /// will be managed exclusive by ByteURL
        init(_ buffer: NIOCore.ByteBuffer) {
            self.buffer = buffer
            self.writtenBytes = buffer.writerIndex
        }
    }
}

extension Internals.ByteURL: Hashable {

    static func == (_ lhs: Internals.ByteURL, _ rhs: Internals.ByteURL) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Data {

    func write(to url: Internals.ByteURL) throws {
        let handle = Internals.ByteHandle(forWritingTo: url)
        try handle.write(contentsOf: self)
        try handle.close()
    }
}
