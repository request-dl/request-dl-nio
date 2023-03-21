/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

public class ByteURL {

    lazy var buffer = ByteBuffer()
    public var writtenBytes: Int = .zero

    public init() {}
}

extension Data {

    func write(to url: ByteURL) throws {
        let handle = ByteHandle(forWritingTo: url)
        try handle.write(contentsOf: self)
        try handle.close()
    }
}
