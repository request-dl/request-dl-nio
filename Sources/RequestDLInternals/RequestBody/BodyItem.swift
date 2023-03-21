/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct BodyItem: BodyContent {

    fileprivate var buffer: BufferProtocol

    public init<Data: DataProtocol>(_ data: Data) {
        self.init(DataBuffer(data))
    }

    public init<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        self.init(DataBuffer(bytes))
    }

    public init(_ url: URL) {
        self.init(FileBuffer(url))
    }

    public init(_ url: ByteURL) {
        self.init(DataBuffer(url))
    }

    public init(_ string: String) {
        self.init(DataBuffer(string))
    }

    public init(_ staticString: StaticString) {
        self.init(DataBuffer(staticString))
    }

    public init<Buffer: BufferProtocol>(_ buffer: Buffer) {
        self.buffer = buffer
    }

    public static func makeBody(_ content: BodyItem, in context: _ContextBody) {
        context.append(content.buffer)
    }
}
