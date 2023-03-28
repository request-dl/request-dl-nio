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
        guard
            let path = bundle.resolveURL(forResourceName: {
                let pathExtension = ".\(format().pathExtension)"
                if file.hasSuffix(pathExtension) {
                    return file
                } else {
                    return "\(file)\(pathExtension)"
                }
            }())?.absolutePath()
        else {
            Internals.Log.failure(
                """
                An error occurred while trying to access an invalid file path.
                """
            )
        }

        self.init(
            path,
            format: format
        )
    }

    public var body: Never {
        bodyException()
    }
}

extension Certificate {

    public static func _makeProperty(
        property: _GraphValue<Certificate>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let inputs = inputs[self]

        return .init(Leaf(SecureConnectionNode(
            CertificateNode(
                source: property.source,
                property: inputs.environment.certificateProperty,
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
}
