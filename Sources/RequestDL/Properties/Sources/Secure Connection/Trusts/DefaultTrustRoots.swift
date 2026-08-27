//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A structure that represents default trust roots.
///
/// > Note: Does not require an enclosing ``SecureConnection`` — a base secure connection
/// configuration is created automatically the first time it's needed. Nest it inside a
/// ``SecureConnection`` only when also configuring other secure connection settings alongside it.
public struct DefaultTrustRoots: Property {

    private struct Node: SecureConnectionPropertyNode {

        func make(_ secureConnection: inout Internals.SecureConnection) {
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

    ///
    /// Initializes a new instance of the DefaultTrustRoots structure.
    ///
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
