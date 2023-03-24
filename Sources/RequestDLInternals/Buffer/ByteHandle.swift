/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

public class ByteHandle {

    private let mode: Mode
    private let url: ByteURL
    private var isClosed = false

    private var index: UInt64 = .zero

    public init(forWritingTo url: ByteURL) {
        self.mode = .write
        self.url = url
    }

    public init(forReadingFrom url: ByteURL) {
        self.mode = .read
        self.url = url
    }

    public func seek(toOffset offset: UInt64) throws {
        precondition(offset >= .zero)

        guard !isClosed else {
            throw ByteHandleError.closed
        }

        index = offset
    }

    public func read(upToCount count: Int) throws -> Data? {
        precondition(count >= .zero)
        guard !isClosed else {
            throw ByteHandleError.closed
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

    public func offset() throws -> UInt64 {
        guard !isClosed else {
            throw ByteHandleError.closed
        }

        return index
    }

    public func write<T: DataProtocol>(contentsOf data: T) throws {
        guard !isClosed else {
            throw ByteHandleError.closed
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

    public func close() throws {
        guard !isClosed else {
            throw ByteHandleError.closed
        }

        isClosed = true
    }
}

private enum ByteHandleError: Error {

    case closed
}

extension ByteHandle {

    fileprivate enum Mode {
        case write
        case read
    }
}
