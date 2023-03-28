/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol SecureConnectionPropertyNode {

    func make(_ secureConnection: inout Internals.SecureConnection)
}

struct SecureConnectionNode: PropertyNode {

    private let node: SecureConnectionPropertyNode

    init(_ node: SecureConnectionPropertyNode) {
        self.node = node
    }

    func make(_ make: inout Make) async throws {
        guard var secureConnection = make.configuration.secureConnection else {
            Internals.Log.failure(
                """
                An attempt was made to access the secure connection, but \
                the required property could not be found.

                Please verify that the property is correctly set up inside \
                the SecureConnection property.
                """
            )
        }

        passthrough(&secureConnection)
        make.configuration.secureConnection = secureConnection
    }
}

extension SecureConnectionNode {

    struct Contains {

        fileprivate let node: SecureConnectionPropertyNode

        func callAsFunction<Property: SecureConnectionPropertyNode>(_ type: Property.Type) -> Bool {
            node is Property
        }
    }

    var contains: Contains {
        .init(node: node)
    }
}

extension SecureConnectionNode {

    struct Passthrough {

        fileprivate let node: SecureConnectionPropertyNode

        func callAsFunction(_ secureConnection: inout Internals.SecureConnection) {
            node.make(&secureConnection)
        }
    }

    var passthrough: Passthrough {
        .init(node: node)
    }
}
