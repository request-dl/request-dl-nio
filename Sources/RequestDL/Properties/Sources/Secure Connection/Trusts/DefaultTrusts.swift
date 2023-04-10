/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents default trusts.
 */
public struct DefaultTrusts: Property {

    /**
     Initializes a new instance of the DefaultTrusts structure.
     */
    public init() {}

    /// Returns an exception since `Never` is a type that can never be constructed.
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

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<DefaultTrusts>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(Node())))
    }
}
