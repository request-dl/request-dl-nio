/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    class ByteURL {

        lazy var buffer = NIOCore.ByteBuffer()
        var writtenBytes: Int = .zero

        init() {}
    }
}

extension Data {

    func write(to url: Internals.ByteURL) throws {
        let handle = Internals.ByteHandle(forWritingTo: url)
        try handle.write(contentsOf: self)
        try handle.close()
    }
}
