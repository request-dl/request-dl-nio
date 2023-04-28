/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a private key for `SecureConnection` configuration.
@RequestActor
public struct PrivateKey: Property {

    fileprivate enum Source {
        case file(String)
        case privateKey(Internals.PrivateKey)
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
    public init(_ file: String, format: Certificate.Format = .pem) {
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
    public init(_ bytes: [UInt8], format: Certificate.Format = .pem) {
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
    ) {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format
        )
    }

    /// Creates a private key from a file with the specified format, and allows for providing a
    /// `NIOSSLSecureBytes` password..
    ///
    /// - Parameters:
    ///   - file: The path to the file containing the private key.
    ///   - format: The format of the private key file. Default is `.pem`.
    ///   - password: The password  for the private key.
    public init(
        _ file: String,
        format: Certificate.Format = .pem,
        password: NIOSSLSecureBytes
    ) {
        self.init(.privateKey(.init(
            file,
            format: format(),
            password: password
        )))
    }

    /// Creates a private key from bytes with the specified format, and allows for providing a
    /// `NIOSSLSecureBytes` password.
    ///
    /// - Parameters:
    ///   - bytes: The bytes representing the private key.
    ///   - format: The format of the private key bytes. Default is `.pem`.
    ///   - password: The password  for the private key.
    public init(
        _ bytes: [UInt8],
        format: Certificate.Format = .pem,
        password: NIOSSLSecureBytes
    ) {
        self.init(.privateKey(.init(
            bytes,
            format: format(),
            password: password
        )))
    }

    /// Creates a private key from a file in the specified bundle with the specified format, and allows for
    /// providing a `NIOSSLSecureBytes` password.
    ///
    /// - Parameters:
    ///   - file: The name of the file containing the private key.
    ///   - bundle: The bundle containing the file.
    ///   - format: The format of the private key file. Default is `.pem`.
    ///   - password: The password  for the private key.
    public init(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem,
        password: NIOSSLSecureBytes
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

@available(*, deprecated, message: "Updates the password closure with NIOSSLSecureBytes")
extension PrivateKey {

    /// Creates a private key from a file with the specified format, and allows for providing a password
    /// callback closure.
    ///
    /// - Parameters:
    ///   - file: The path to the file containing the private key.
    ///   - format: The format of the private key file. Default is `.pem`.
    ///   - password: A closure that will be called with a password callback closure as its argument.
    ///   The password callback closure should be invoked with the password for the private key.
    public init<Password: Collection>(
        _ file: String,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) where Password.Element == UInt8 {
        var passwordBytes = NIOSSLSecureBytes()
        password { password in
            passwordBytes.append(contentsOf: password)
        }

        self.init(
            file,
            format: format,
            password: passwordBytes
        )
    }

    /// Creates a private key from bytes with the specified format, and allows for providing a password
    /// callback closure.
    ///
    /// - Parameters:
    ///   - bytes: The bytes representing the private key.
    ///   - format: The format of the private key bytes. Default is `.pem`.
    ///   - password: A closure that will be called with a password callback closure as its argument.
    ///   The password callback closure should be invoked with the password for the private key.
    public init<Password: Collection>(
        _ bytes: [UInt8],
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) where Password.Element == UInt8 {
        var passwordBytes = NIOSSLSecureBytes()
        password { password in
            passwordBytes.append(contentsOf: password)
        }

        self.init(
            bytes,
            format: format,
            password: passwordBytes
        )
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
    public init<Password: Collection>(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) where Password.Element == UInt8 {
        var passwordBytes = NIOSSLSecureBytes()
        password { password in
            passwordBytes.append(contentsOf: password)
        }

        self.init(
            file,
            in: bundle,
            format: format,
            password: passwordBytes
        )
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
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<PrivateKey>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .init(Leaf(SecureConnectionNode(
            Node(source: property.source)
        )))
    }
}
