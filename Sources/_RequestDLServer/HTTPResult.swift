/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct HTTPResult<Response: Codable>: Codable {

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
}
