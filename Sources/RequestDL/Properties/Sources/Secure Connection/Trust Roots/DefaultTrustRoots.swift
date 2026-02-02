/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A structure that represents default trusts.
@available(*, deprecated, renamed: "DefaultTrustRoots")
public typealias DefaultTrusts = DefaultTrustRoots

/// A structure that represents default trust roots.
public struct DefaultTrustRoots: Property {

    private struct Node: SecureConnectionPropertyNode {

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            secureConnection.trustRoots = nil
            secureConnection.useDefaultTrustRoots = true
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Inits

    /**
     Initializes a new instance of the DefaultTrustRoots structure.
     */
    public init() {}

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<DefaultTrustRoots>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            SecureConnectionNode(
                Node(),
                logger: inputs.environment.logger
            )
        )
    }
}
