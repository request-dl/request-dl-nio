/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing a private key for `SecureConnection` configuration.
public struct PrivateKey<Password: Collection>: Property where Password.Element == UInt8 {

    fileprivate enum Source {
        case file(String)
        case privateKey(Internals.PrivateKey<Password>)
    }

    private let source: Source

    private init(_ source: Source) {
        self.source = source
    }

    /// Creates a private key from a file with the specified format without password.
    ///
    /// - Parameters:
    ///   - file: The path to the file containing the private key.
    ///   - format: The format of the private key file. Default is `.pem`.
    public init(_ file: String, format: Certificate.Format = .pem) where Password == [UInt8] {
        switch format {
        case .pem:
            self.init(.file(file))
        case .der:
            self.init(.privateKey(.init(file, format: format())))
        }
    }

    /// Creates a private key from bytes with the specified format without password.
    ///
    /// - Parameters:
    ///   - bytes: The bytes representing the private key.
    ///   - format: The format of the private key bytes. Default is `.pem`.
    public init(_ bytes: [UInt8], format: Certificate.Format = .pem) where Password == [UInt8] {
        self.init(.privateKey(.init(
            bytes,
            format: format()
        )))
    }

    /// Creates a private key from a file in the specified bundle with the specified format without password.
    ///
    /// - Parameters:
    ///   - file: The name of the file containing the private key.
    ///   - bundle: The bundle containing the file.
    ///   - format: The format of the private key file. Default is `.pem`.
    public init(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem
    ) where Password == [UInt8] {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format
        )
    }

    /// Creates a private key from a file with the specified format, and allows for providing a password
    /// callback closure.
    ///
    /// - Parameters:
    ///   - file: The path to the file containing the private key.
    ///   - format: The format of the private key file. Default is `.pem`.
    ///   - password: A closure that will be called with a password callback closure as its argument.
    ///   The password callback closure should be invoked with the password for the private key.
    public init(
        _ file: String,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            file,
            format: format(),
            password: password
        )))
    }

    /// Creates a private key from bytes with the specified format, and allows for providing a password
    /// callback closure.
    ///
    /// - Parameters:
    ///   - bytes: The bytes representing the private key.
    ///   - format: The format of the private key bytes. Default is `.pem`.
    ///   - password: A closure that will be called with a password callback closure as its argument.
    ///   The password callback closure should be invoked with the password for the private key.
    public init(
        _ bytes: [UInt8],
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            bytes,
            format: format(),
            password: password
        )))
    }

    /// Creates a private key from a file in the specified bundle with the specified format, and allows for
    /// providing a password callback closure.
    ///
    /// - Parameters:
    ///   - file: The name of the file containing the private key.
    ///   - bundle: The bundle containing the file.
    ///   - format: The format of the private key file. Default is `.pem`.
    ///   - password: A closure that will be called with a password callback closure as its argument.
    ///   The password callback closure should be invoked with the password for the private key.
    public init(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format,
            password: password
        )
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension PrivateKey {

    private struct Node: SecureConnectionPropertyNode {

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) {
            switch source {
            case .file(let file):
                secureConnection.privateKey = .file(file)
            case .privateKey(let privateKey):
                secureConnection.privateKey = .privateKey(privateKey)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PrivateKey<Password>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(
            Node(source: property.source)
        )))
    }
}
