/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PropertyNode: Sendable, NodeStringConvertible {

    func make(_ make: inout Make) async throws
}

extension PropertyNode {

    var nodeDescription: String {
        #if DEBUG
        return NodeDebug(self).describe()
        #else
        return String(describing: self)
        #endif
    }
}
