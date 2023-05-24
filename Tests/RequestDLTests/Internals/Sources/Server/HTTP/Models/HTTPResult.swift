/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct HTTPResult<Response: Codable>: Codable, Equatable where Response: Equatable {

    let receivedBytes: Int
    let base64: String?
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
