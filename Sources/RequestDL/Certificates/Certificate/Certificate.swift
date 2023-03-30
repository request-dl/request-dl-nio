/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Certificate: Property {

    private let source: CertificateNode.Source
    private let format: Format

    public init<Bytes: Sequence>(
        _ bytes: Bytes,
        format: Format = .pem
    ) where Bytes.Element == UInt8 {
        self.source = .bytes(Array(bytes))
        self.format = format
    }

    public init(_ file: String, format: Format = .pem) {
        self.source = .file(file)
        self.format = format
    }

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
        let inputs = inputs[self]

        guard let certificateProperty = inputs.environment.certificateProperty else {
            Internals.Log.failure(
                """
                It seems that you are attempting to create a Certificate \
                property outside of the allowed context.

                Please note that Certificates, Trusts, and AdditionalTrusts \
                are the only valid contexts in which you can create a \
                Certificate property.

                Please ensure that you are creating your Certificate property \
                within one of these contexts to avoid encountering this error.
                """
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
                """
                An error occurred while trying to access an invalid file path.
                """
            )
        }

        return resourceURL.absolutePath()
    }
}
