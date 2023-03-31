/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Use `Trusts` to establish trust for a server certificate file within your app.
public struct Trusts<Content: Property>: Property {

    let file: String
    let bundle: Bundle

    /**
     Initializes a new instance of `Trusts` with the given certificate file and bundle.

     - Parameters:
        - file: The name of the certificate file to trust.
        - bundle: The bundle that contains the certificate file.
     */
    public init(
        _ file: String,
        in bundle: Bundle
    ) where Content == Never {
        self.file = file
        self.bundle = bundle
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Trusts {

    private struct Node: SecureConnectionPropertyNode {

        let file: String
        let bundle: Bundle

        func make(_ make: inout Make) async throws {
            try await ServerTrustNode(certificates: [
                Certificate(file, in: bundle)
            ]).make(&make)
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Trusts<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]

        return .init(Leaf(SecureConnectionNode(
            Node(
                file: property.file,
                bundle: property.bundle
            )
        )))
    }
}
