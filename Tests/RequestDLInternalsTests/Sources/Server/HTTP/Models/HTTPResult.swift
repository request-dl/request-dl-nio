//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
#endif

struct HTTPResult<Response: Codable>: Codable, Equatable where Response: Equatable {

    let receivedBytes: Int
    let response: Response
}

extension HTTPResult {

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    init(_ data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
