/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A property that represents an X.509 certificate.
///
/// Use a `Certificate` property to specify an X.509 certificate that is used for secure communication
/// over a network. A `Certificate` can be initialized with a sequence of bytes, a file path, or a file path
/// within a bundle. You can also specify the format of the certificate using the `format` parameter.
///
/// ```swift
/// let certData = Data(base64Encoded: "...")
/// let cert = Certificate(certData!, format: .der)
/// ```
public struct Certificate: Property {

    private let source: CertificateNode.Source
    private let format: Format

    /// Creates a `Certificate` property with the specified bytes and format.
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

    /// Creates a `Certificate` property with the specified file path and format.
    ///
    /// - Parameters:
    ///    - file: The path to the file that contains the certificate.
    ///    - format: The format of the certificate (default: .pem).
    public init(_ file: String, format: Format = .pem) {
        self.source = .file(file)
        self.format = format
    }

    /// Creates a `Certificate` property with the specified file path within a bundle and format.
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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Certificate {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Certificate>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertIfNeeded()

        guard let certificateProperty = inputs.environment.certificateProperty else {
            Internals.Log.failure(
                .cantCreateCertificateOutsideSecureConnection()
            )
        }

        return .init(Leaf(SecureConnectionNode(
            CertificateNode(
                source: property.source,
                property: certificateProperty,
                format: property.format()
            )
        )))
    }
}

extension Certificate {

    public enum Format {
        case pem
        case der
    }
}

extension Certificate.Format {

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
