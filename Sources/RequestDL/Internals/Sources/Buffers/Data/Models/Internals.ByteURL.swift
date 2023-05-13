/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    final class ByteURL: @unchecked Sendable {

        // MARK: - Internal properties

        var buffer: NIOCore.ByteBuffer {
            get { lock.withLock { _buffer } }
            set { lock.withLock { _buffer = newValue } }
        }

        var writtenBytes: Int {
            get { lock.withLock { _writtenBytes } }
            set { lock.withLock { _writtenBytes = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private lazy var _buffer = NIOCore.ByteBuffer()
        private var _writtenBytes: Int = .zero

        // MARK: - Inits

        init() {}

        /// This should only be used to wraps a ByteBuffer that
        /// will be managed exclusive by ByteURL
        init(_ buffer: NIOCore.ByteBuffer) {
            self._buffer = buffer
            self._writtenBytes = buffer.writerIndex
        }
    }
}

// MARK: - Hashable

extension Internals.ByteURL: Hashable {

    static func == (_ lhs: Internals.ByteURL, _ rhs: Internals.ByteURL) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - Data extension

extension Data {

    func write(to url: Internals.ByteURL) throws {
        let handle = Internals.ByteHandle(forWritingTo: url)
        try handle.write(contentsOf: self)
        try handle.close()
    }
}
