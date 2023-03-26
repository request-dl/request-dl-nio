/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct HTTPResult<Response: Codable>: Codable, Equatable where Response: Equatable {

    public internal(set) var receivedBytes: Int
    public let response: Response

    public init(
        receivedBytes: Int,
        response: Response
    ) {
        self.receivedBytes = receivedBytes
        self.response = response
    }
}

extension HTTPResult {

    public func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func resolve(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
