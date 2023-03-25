/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum CertificateSource {

    case certificate(Certificate)

    /// PEM format
    case bytes([UInt8])

    /// PEM format
    case file(String)
}

extension CertificateSource {

    func build() throws -> [NIOSSLCertificate] {
        switch self {
        case .certificate(let certificate):
            return try [certificate.build()]
        case .bytes(let bytes):
            return try NIOSSLCertificate.fromPEMBytes(bytes)
        case .file(let file):
            return try NIOSSLCertificate.fromPEMFile(file)
        }
    }
}
