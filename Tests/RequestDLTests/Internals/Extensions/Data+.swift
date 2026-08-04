//
// See LICENSE for this package's licensing information.
//

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

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
        // `.rounded(.down)`, not the free function `floor(_:)` — that comes from `Glibc`/
        // `Darwin`, neither of which this file imports under `FoundationEssentials`.
        let chunk = Int((Double(length) / Double(max)).rounded(.down))

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

    /// The "&"-separated query pairs, decoded as UTF-8 — the only encoding any call site uses.
    ///
    /// - Note: `String.Encoding` is not part of `FoundationEssentials`. `String(decoding:as:)`
    /// needs no import at all, and substitutes U+FFFD for anything malformed rather than
    /// failing, which is fine here: a malformed query is still a string the comparison this
    /// backs can fail on.
    func queries() -> Set<String> {
        Set(String(decoding: self, as: UTF8.self).split(separator: "&").map { String($0) })
    }

    /// Decodes bytes produced by `Charset.utf16`'s encoder: two bytes per code unit, with a
    /// leading byte order mark.
    ///
    /// - Note: `String(data:encoding:)`/`String.Encoding` are not part of `FoundationEssentials`.
    /// `String(decoding:as:)` takes code units, not bytes, so the byte order has to be resolved
    /// by hand first — the reverse of what `Charset.utf16`'s encoder does.
    func decodedUTF16String() -> String? {
        var bytes = Array(self)

        guard bytes.count >= 2 else { return nil }

        let bigEndian: Bool
        switch (bytes[0], bytes[1]) {
        case (0xFE, 0xFF):
            bigEndian = true
            bytes.removeFirst(2)
        case (0xFF, 0xFE):
            bigEndian = false
            bytes.removeFirst(2)
        default:
            return nil
        }

        guard bytes.count.isMultiple(of: 2) else { return nil }

        var units = [UInt16]()
        units.reserveCapacity(bytes.count / 2)

        for index in stride(from: 0, to: bytes.count, by: 2) {
            let first = UInt16(bytes[index])
            let second = UInt16(bytes[index + 1])
            units.append(bigEndian ? (first << 8) | second : (second << 8) | first)
        }

        return String(decoding: units, as: UTF16.self)
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
