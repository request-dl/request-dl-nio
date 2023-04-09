/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct HTTPResult<Response: Codable>: Codable, Equatable where Response: Equatable {

    internal(set) var receivedBytes: Int
    let response: Response

    init(
        receivedBytes: Int,
        response: Response
    ) {
        self.receivedBytes = receivedBytes
        self.response = response
    }
}

extension HTTPResult {

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    init(_ data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
