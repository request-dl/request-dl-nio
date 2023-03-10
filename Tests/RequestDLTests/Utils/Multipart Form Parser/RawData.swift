/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct RawData {

    fileprivate let bytes: [Byte]

    fileprivate init(_ bytes: [Byte]) {
        self.bytes = bytes
    }

    init(bytes: [UInt8] = []) {
        self.init(bytes.map { .init(rawValue: $0) })
    }

    init(from data: Data) {
        self.init(data.map { .init(rawValue: $0) })
    }

    func appending(_ byte: Byte) -> RawData {
        .init(bytes + [byte])
    }

    func split(separator: Character) throws -> [RawData] {
        let separator = separator.utf8.map { Byte(rawValue: $0) }

        return bytes.components(
            separatedBy: separator,
            omittingEmptySubsequences: false
        ).map { RawData($0) }
    }

    var isEmpty: Bool {
        bytes.isEmpty
    }

    func hasSuffix<S: StringProtocol>(_ suffix: S) -> Bool {
        let endIndex = bytes.endIndex
        let index = bytes.index(endIndex, offsetBy: -suffix.utf8.count)
        let bytes = bytes[index ..< endIndex]

        return Self.equal(bytes, to: suffix)
    }

    func data() -> Data {
        Data(bytes.map { $0.rawValue })
    }

    static func equal<Bytes: RandomAccessCollection, S: StringProtocol>(
        _ bytes: Bytes,
        to string: S
    ) -> Bool where Bytes.Element == Byte {
        let stringBytes = string.utf8

        guard bytes.count == stringBytes.count else {
            return false
        }

        return stringBytes.enumerated().allSatisfy { index, byte in
            bytes[bytes.index(bytes.startIndex, offsetBy: index)] == byte
        }
    }

    static func == <S: StringProtocol>(_ lhs: Self, _ rhs: S) -> Bool {
        equal(lhs.bytes, to: rhs)
    }
}

extension Optional<RawData> {

    static func == <S: StringProtocol>(_ lhs: Self, _ rhs: S) -> Bool {
        lhs.map {
            $0 == rhs
        } ?? false
    }
}

extension RawData {

    enum ReadingError: Error {
        case invalidByte
    }
}

extension RawData {

    struct Byte: Equatable {

        let rawValue: UInt8

        static func == (_ lhs: Self, _ rhs: UInt8) -> Bool {
            lhs.rawValue == rhs
        }
    }
}

extension Array<RawData> {

    func joined(by character: Character) -> RawData {
        guard let first = first else {
            return .init()
        }

        return dropFirst().reduce(first) {
            var mutableData = $0

            for byte in character.utf8 {
                mutableData = mutableData.appending(.init(rawValue: byte))
            }

            for byte in $1.bytes {
                mutableData = mutableData.appending(byte)
            }

            return mutableData
        }
    }
}
