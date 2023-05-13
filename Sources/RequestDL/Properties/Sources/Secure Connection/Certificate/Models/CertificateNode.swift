/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct CertificateNode: SecureConnectionCollectorPropertyNode {

    enum Source: Sendable, Hashable {
        case bytes([UInt8])
        case file(String)

        fileprivate func build(_ format: Internals.Certificate.Format) -> Internals.Certificate {
            switch self {
            case .bytes(let bytes):
                return .init(bytes, format: format)
            case .file(let file):
                return .init(file, format: format)
            }
        }
    }

    // MARK: - Internal properties

    let source: Source
    let property: CertificateProperty
    let format: Internals.Certificate.Format

    // MARK: - Internal methods

    func make(_ collector: inout SecureConnectionNode.Collector) {
        switch property {
        case .chain:
            var certificateChain = collector.certificateChain ?? []
            certificateChain.append(source.build(format))
            collector.certificateChain = certificateChain
        case .trust:
            var trustRoots = collector.trustRoots ?? []
            trustRoots.append(source.build(format))
            collector.trustRoots = trustRoots
        case .additionalTrust:
            var certificateChain = collector.additionalTrustRoots ?? []
            certificateChain.append(source.build(format))
            collector.additionalTrustRoots = certificateChain
        }
    }
}
