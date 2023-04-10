/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents the description of a PSK client.
 */
public struct PSKClientDescription: PSKDescription {

    /// A string representing a hint for the server to use in order to locate the PSK identity.
    public let serverHint: String

    init(_ serverHint: String) {
        self.serverHint = serverHint
    }
}
