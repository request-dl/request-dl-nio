/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    class ByteHandle {

        private let mode: Mode
        private let url: ByteURL
        private var isClosed = false

        private var index: UInt64 = .zero

        init(forWritingTo url: ByteURL) {
            self.mode = .write
            self.url = url
        }

        init(forReadingFrom url: ByteURL) {
            self.mode = .read
            self.url = url
        }
    }
}

extension Internals.ByteHandle {

    func seek(toOffset offset: UInt64) throws {
        precondition(offset >= .zero)

        guard !isClosed else {
            throw ClosedError()
        }

        index = offset
    }

    func offset() throws -> UInt64 {
        guard !isClosed else {
            throw ClosedError()
        }

        return index
    }
}

extension Internals.ByteHandle {

    func read(upToCount count: Int) throws -> Data? {
        precondition(count >= .zero)
        guard !isClosed else {
            throw ClosedError()
        }

        switch mode {
        case .write:
            return nil
        case .read:
            guard count > .zero else {
                return nil
            }

            let index = Int(index)
            precondition(count + index <= url.writtenBytes)

            url.buffer.moveWriterIndex(to: url.writtenBytes)
            url.buffer.moveReaderIndex(to: index)

            let data = url.buffer.readData(length: count)
            self.index = UInt64((data == nil ? .zero : count) + index)
            return data
        }
    }

    func write<T: DataProtocol>(contentsOf data: T) throws {
        guard !isClosed else {
            throw ClosedError()
        }

        switch mode {
        case .write:
            let index = Int(index)

            url.buffer.moveReaderIndex(to: .zero)
            url.buffer.moveWriterIndex(to: index)

            let written = url.buffer.writeData(data)
            url.writtenBytes = max(url.writtenBytes, url.buffer.writerIndex)

            self.index += UInt64(written)
        case .read:
            return
        }
    }
}

extension Internals.ByteHandle {

    func close() throws {
        guard !isClosed else {
            throw ClosedError()
        }

        isClosed = true
    }
}

extension Internals.ByteHandle {

    fileprivate struct ClosedError: Error {

        init() {}
    }
}

extension Internals.ByteHandle {

    fileprivate enum Mode {
        case write
        case read
    }
}
