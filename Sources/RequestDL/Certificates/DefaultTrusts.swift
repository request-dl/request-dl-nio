/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct DefaultTrusts: Property {

    public init() {}

    public var body: Never {
        bodyException()
    }
}

extension DefaultTrusts {

    private struct Node: SecureConnectionPropertyNode {

        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection.trustRoots = .default
        }
    }

    public static func _makeProperty(
        property: _GraphValue<DefaultTrusts>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(Node())))
    }
}
