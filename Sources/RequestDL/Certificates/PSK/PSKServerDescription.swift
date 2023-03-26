/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PSKServerDescription: PSKDescription {

    public let serverHint: String
    public let clientHint: String

    init(
        serverHint: String,
        clientHint: String
    ) {
        self.serverHint = serverHint
        self.clientHint = clientHint
    }
}
