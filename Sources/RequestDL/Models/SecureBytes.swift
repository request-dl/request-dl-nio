/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct SecureBytes: Sendable, Equatable {

    private var _bytes: Internals.NIOSSLSecureBytes

    init(_ secureBytes: Internals.NIOSSLSecureBytes) {
        self._bytes = secureBytes
    }

    public init() {
        self._bytes = .init()
    }
}

extension SecureBytes {

    public mutating func append<C: Collection>(_ data: C) where C.Element == UInt8 {
        _bytes.append(data)
    }

    public mutating func reserveCapacity(_ n: Int) {
        _bytes.reserveCapacity(n)
    }
}

extension SecureBytes: RandomAccessCollection {

    public var startIndex: Int {
        _bytes.startIndex
    }

    public var endIndex: Int {
        _bytes.endIndex
    }

    public var count: Int {
        _bytes.count
    }

    public subscript(index: Int) -> UInt8 {
        get { _bytes[index] }
        set { _bytes[index] = newValue }
    }
}

extension SecureBytes: MutableCollection {}

extension SecureBytes: RangeReplaceableCollection {

    public mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Index>,
        with newElements: C
    ) where C.Element == UInt8 {
        _bytes.replaceSubrange(subrange, with: newElements)
    }
}

extension SecureBytes {

    func build() -> Internals.NIOSSLSecureBytes {
        _bytes
    }
}
