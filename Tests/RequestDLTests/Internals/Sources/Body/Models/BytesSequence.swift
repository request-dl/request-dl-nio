//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct BytesSequence: Sequence {

    private let data: Data

    init(_ data: Data) {
        self.data = data
    }

    func makeIterator() -> Iterator {
        .init(Array(data))
    }
}

extension BytesSequence {

    struct Iterator: IteratorProtocol {

        private var bytes: [UInt8]

        fileprivate init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func next() -> UInt8? {
            guard bytes.first != nil else {
                return nil
            }

            return bytes.removeFirst()
        }
    }
}
