/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents the description of a PSK server.
 */
@available(*, deprecated, renamed: "SSLPSKServerIdentityResolver")
public struct PSKServerDescription: PSKDescription {

    /// A string representing a hint for the server to use in order to locate the PSK identity.
    public let serverHint: String

    /// A string representing a hint for the client to use in order to locate the PSK identity.
    public let clientHint: String

    init(
        serverHint: String,
        clientHint: String
    ) {
        self.serverHint = serverHint
        self.clientHint = clientHint
    }
}
