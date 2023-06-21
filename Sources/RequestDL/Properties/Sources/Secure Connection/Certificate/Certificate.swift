/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Set a certificate of type `PEM` or `DER`.

 It should be used to configure the ``RequestDL/SecureConnection`` and make the connection secure with the server. There are several options to utilize the ``RequestDL/Certificate``.

 You can use it to configure the ``RequestDL/Trusts`` or ``RequestDL/AdditionalTrusts`` to validate if the server is trustworthy.

 Another valid option is to use it with ``RequestDL/Certificates`` and send client authentication certificates to the server.

 ```swift
 let certData = Data(base64Encoded: "...")
 let cert = Certificate(certData!, format: .der)
 ```
 */
public struct Certificate: Property {

    public enum Format: Sendable, Hashable {

        case pem
        case der

        func callAsFunction() -> Internals.Certificate.Format {
            switch self {
            case .der:
                return .der
            case .pem:
                return .pem
            }
        }

        func resolve(for path: String, in bundle: Bundle) -> String {
            let resourceName: String = {
                let pathExtension = ".\(self().pathExtension)"

                if path.hasSuffix(pathExtension) {
                    return path
                } else {
                    return "\(path)\(pathExtension)"
                }
            }()

            guard let resourceURL = bundle.resolveURL(forResourceName: resourceName) else {
                Internals.Log.failure(
                    .cantOpenCertificateFile(
                        resourceName,
                        bundle
                    )
                )
            }

            return resourceURL.absolutePath(percentEncoded: false)
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: CertificateNode.Source
    private let format: Format

    // MARK: - Inits

    /// Initializes with the specified bytes and format.
    ///
    /// - Parameters:
    ///    - bytes: A sequence of bytes that represent the certificate.
    ///    - format: The format of the certificate (default: .pem).
    public init<Bytes: Sequence>(
        _ bytes: Bytes,
        format: Format = .pem
    ) where Bytes.Element == UInt8 {
        self.source = .bytes(Array(bytes))
        self.format = format
    }

    /// Initializes with the specified file path and format.
    ///
    /// - Parameters:
    ///    - file: The path to the file that contains the certificate.
    ///    - format: The format of the certificate (default: .pem).
    public init(_ file: String, format: Format = .pem) {
        self.source = .file(file)
        self.format = format
    }

    /// Initializes with the specified file path within a bundle and format.
    ///
    /// - Parameters:
    ///    - file: The path to the file that contains the certificate, relative to the specified bundle.
    ///    - bundle: The bundle that contains the file.
    ///    - format: The format of the certificate (default: .pem).
    public init(
        _ file: String,
        in bundle: Bundle,
        format: Format = .pem
    ) {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format
        )
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Certificate>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        guard let certificateProperty = inputs.environment.certificateProperty else {
            Internals.Log.failure(
                .cantCreateCertificateOutsideSecureConnection()
            )
        }

        return .leaf(SecureConnectionNode(
            CertificateNode(
                source: property.source,
                property: certificateProperty,
                format: property.format()
            )
        ))
    }
}
