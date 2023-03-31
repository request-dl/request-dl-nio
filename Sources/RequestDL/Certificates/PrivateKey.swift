/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A representation of a client certificate that can be used in an HTTP request.

 This type conforms to the `Property` protocol, which means it can be used as a property in a
 `RequestBuilder`. It has one initializer that takes the certificate name, bundle, and password.
 */
public struct PrivateKey<Password: Collection>: Property where Password.Element == UInt8 {

    let file: String
    let bundle: Bundle
    let password: ((Password) -> Void) -> Void

    /**
     Creates a new instance of PrivateKey with the given certificate name, bundle, and password.

     - Parameters:
        - file: The name of the certificate.
        - bundle: The bundle in which the certificate is located.
        - password: The password to access the certificate.
     */
    public init(
        _ file: String,
        in bundle: Bundle,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.file = file
        self.bundle = bundle
        self.password = password
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension PrivateKey {

    private struct Node: SecureConnectionPropertyNode {

        let file: String
        let bundle: Bundle
        let password: ((Password) -> Void) -> Void

        func make(_ make: inout Make) async throws {
            let password: Password = await withUnsafeContinuation { continuation in
                self.password {
                    continuation.resume(returning: $0)
                }
            }

            guard let password = String(data: Data(password), encoding: .utf8) else {
                fatalError("Couldn't resolve password into string")
            }

            try await ClientCertificateNode(
                source: .bundle(file, bundle),
                password: password
            ).make(&make)
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PrivateKey<Password>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(
            Node(
                file: property.file,
                bundle: property.bundle,
                password: property.password
            )
        )))
    }
}
