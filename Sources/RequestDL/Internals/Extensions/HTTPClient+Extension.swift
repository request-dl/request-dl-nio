/*
 See LICENSE for this package's licensing information.
*/

import AsyncHTTPClient

extension HTTPClient.Decompression: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        "\(lhs)" == "\(rhs)"
    }
}

extension HTTPClient.Configuration.RedirectConfiguration: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        "\(lhs)" == "\(rhs)"
    }
}
