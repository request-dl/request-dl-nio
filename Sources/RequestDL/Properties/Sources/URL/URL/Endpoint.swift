/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Endpoint: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let endpoint: String

    // MARK: - Init

    public init<S: StringProtocol>(_ endpoint: S) {
        self.endpoint = String(endpoint)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Endpoint>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(URLNode(endpoint: property.endpoint))
    }
}
