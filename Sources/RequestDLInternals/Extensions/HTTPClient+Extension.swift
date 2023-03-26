/*
 See LICENSE for this package's licensing information.
*/

import AsyncHTTPClient

extension HTTPClient.Decompression: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        "\(lhs)" == "\(rhs)"
    }
}

extension HTTPClient.Configuration.RedirectConfiguration: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        "\(lhs)" == "\(rhs)"
    }
}
