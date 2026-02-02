/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

struct SPKIHashNode: PropertyNode {

    struct Passthrough: Sendable {

        private let node: SPKIHashNode

        init(_ node: SPKIHashNode) {
            self.node = node
        }

        func callAsFunction(_ tlsPinning: inout SPKIPinningConfiguration) throws {
            let hash = try node.source.base64EncodedString()

            switch node.anchor {
            case .primary:
                tlsPinning.primaryPins.insert(hash)
            case .backup:
                tlsPinning.backupPins.insert(hash)
            }
        }
    }

    var passthrough: Passthrough {
        .init(self)
    }

    let anchor: SPKIHashAnchor
    let source: SPKIHashSource

    func make(_ make: inout Make) async throws {}
}
