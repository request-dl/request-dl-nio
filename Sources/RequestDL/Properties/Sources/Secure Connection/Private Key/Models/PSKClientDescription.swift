/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PSKClientDescription: PSKDescription {

    public let serverHint: String

    init(_ serverHint: String) {
        self.serverHint = serverHint
    }
}
