/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

#if !canImport(Network)
/// A struct representing a private key for `SecureConnection` configuration.
public struct PrivateKey: Property {

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

    fileprivate enum Source: Sendable {
        case file(String)
        case privateKey(Internals.PrivateKey)
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: Source

    // MARK: - Inits

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

    private init(_ source: Source) {
        self.source = source
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PrivateKey>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(SecureConnectionNode(
            Node(source: property.source)
        ))
    }
}
#endif
