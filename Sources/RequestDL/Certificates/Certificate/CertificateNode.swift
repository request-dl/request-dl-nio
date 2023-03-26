/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

class CertificateNode: SecureConnectionNode {

    private let source: Source
    private let format: CertificateFormat

    init(
        source: Source,
        format: CertificateFormat
    ) {
        self.source = source
        self.format = format
        super.init {
            Self.resolve(
                source: source,
                format: format,
                property: .additionalTrust,
                secureConnection: &$0
            )
        }
    }

    func callAsFunction(
        _ property: CertificateProperty,
        secureConnection: inout RequestDLInternals.Session.SecureConnection
    ) {
        Self.resolve(
            source: source,
            format: format,
            property: property,
            secureConnection: &secureConnection
        )
    }
}

extension CertificateNode {

    private static func appendCertificateAtChain(
        source: Source,
        format: CertificateFormat,
        secureConnection: inout RequestDLInternals.Session.SecureConnection
    ) {
        var chain = secureConnection.certificateChain ?? .init()

        switch format {
        case .der:
            chain.append(.certificate(source.build(format)))
        case .pem:
            switch source {
            case .bytes(let bytes):
                chain.append(.bytes(bytes))
            case .file(let file):
                chain.append(.file(file))
            }
        }

        secureConnection.certificateChain = chain
    }

    private static func appendCertificateAtTrust(
        source: Source,
        format: CertificateFormat,
        secureConnection: inout RequestDLInternals.Session.SecureConnection
    ) {
        switch format {
        case .der:
            secureConnection.trustRoots = .certificate(
                .certificate(source.build(format))
            )
        case .pem:
            switch source {
            case .bytes(let bytes):
                secureConnection.trustRoots = .certificate(
                    .bytes(bytes)
                )
            case .file(let file):
                secureConnection.trustRoots = .file(file)
            }
        }
    }

    private static func appendCertificateAtAdditionalTrust(
        source: Source,
        format: CertificateFormat,
        secureConnection: inout RequestDLInternals.Session.SecureConnection
    ) {
        var trusts = secureConnection.additionalTrustRoots ?? .init()

        switch format {
        case .der:
            trusts.append(.certificate(
                .certificate(source.build(format))
            ))
        case .pem:
            switch source {
            case .bytes(let bytes):
                trusts.append(.certificate(
                    .bytes(bytes)
                ))
            case .file(let file):
                trusts.append(.file(file))
            }
        }

        secureConnection.additionalTrustRoots = trusts
    }

    fileprivate static func resolve(
        source: Source,
        format: CertificateFormat,
        property: CertificateProperty,
        secureConnection: inout RequestDLInternals.Session.SecureConnection
    ) {
        switch property {
        case .chain:
            appendCertificateAtChain(
                source: source,
                format: format,
                secureConnection: &secureConnection
            )
        case .trust:
            appendCertificateAtTrust(
                source: source,
                format: format,
                secureConnection: &secureConnection
            )
        case .additionalTrust:
            appendCertificateAtAdditionalTrust(
                source: source,
                format: format,
                secureConnection: &secureConnection
            )
        }
    }
}

extension CertificateNode {

    enum Source {
        case bytes([UInt8])
        case file(String)
    }
}

extension CertificateNode.Source {

    fileprivate func build(_ format: CertificateFormat) -> RequestDLInternals.Certificate {
        switch self {
        case .bytes(let bytes):
            return .init(bytes, format: format)
        case .file(let file):
            return .init(file, format: format)
        }
    }
}
