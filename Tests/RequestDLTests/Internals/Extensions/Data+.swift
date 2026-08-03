//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import func Foundation.floor
#endif

@testable import RequestDL

extension Data {

    static func randomParts(_ count: Int, producer: @Sendable (Int) async -> Data) async -> [Data] {
        var items = [Data]()
        items.reserveCapacity(count)
        for index in 0..<count {
            await items.append(producer(index))
        }
        return items
    }

    static func randomData(length: Int) async -> Data {
        guard length > .zero else {
            return Data()
        }

        var buffer = await Internals.DataBuffer()

        let max = length > UInt8.max ? UInt8.max : UInt8(length)
        let chunk = Int(floor(Double(length) / Double(max)))

        for byte in UInt8.min...UInt8.max {
            let availableBytes = length - buffer.writerIndex
            let length = availableBytes > Int(chunk) ? Int(chunk) : availableBytes

            let data = Data(repeating: byte, count: length)
            await buffer.writeData(data)
        }

        if buffer.readableBytes < length {
            await buffer.writeData(Data(repeating: .min, count: length - buffer.readableBytes))
        }

        precondition(buffer.readableBytes == length)

        guard let data = await buffer.readData(buffer.readableBytes) else {
            return Data()
        }

        return Data(data)
    }
}

extension Data {

    func queries(using encoding: String.Encoding) -> Set<String> {
        guard let literal = String(data: self, encoding: encoding) else {
            return []
        }

        return Set(literal.split(separator: "&").map { String($0) })
    }
}

extension Data {

    init<Sequence: AsyncSequence>(_ sequence: Sequence) async throws where Sequence.Element == UInt8 {
        self.init()

        for try await element in sequence {
            append(element)
        }
    }

    init<Sequence: AsyncSequence>(_ sequence: Sequence) async throws where Sequence.Element == Data {
        self.init()

        for try await data in sequence {
            append(contentsOf: data)
        }
    }
}
