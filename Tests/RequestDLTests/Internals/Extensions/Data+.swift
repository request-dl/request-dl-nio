/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

extension Data {

    static func randomData(length: Int) -> Data {
        guard length > .zero else {
            return Data()
        }

        var buffer = Internals.DataBuffer()

        let max = length > UInt8.max ? UInt8.max : UInt8(length)
        let chunk = Int(floor(Double(length) / Double(max)))

        for byte in UInt8.min ... UInt8.max {
            let availableBytes = length - buffer.writerIndex
            let length = availableBytes > Int(chunk) ? Int(chunk) : availableBytes

            let data = Data(repeating: byte, count: length)
            buffer.writeData(data)
        }

        if buffer.readableBytes < length {
            buffer.writeData(Data(repeating: .min, count: length - buffer.readableBytes))
        }

        precondition(buffer.readableBytes == length)

        guard let data = buffer.readData(buffer.readableBytes) else {
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
