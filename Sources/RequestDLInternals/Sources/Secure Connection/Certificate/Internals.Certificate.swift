//
// See LICENSE for this package's licensing information.
//

import NIOSSL

extension Internals {

    package struct Certificate: Sendable, Hashable {

        package enum Source: Hashable {
            case file(String)
            case bytes([UInt8])
        }

        // MARK: - Internal properties

        package let source: Source
        package let format: Format

        // MARK: - Inits

        package init(_ file: String, format: Format) {
            self.source = .file(file)
            self.format = format
        }

        package init(_ bytes: [UInt8], format: Format) {
            self.source = .bytes(bytes)
            self.format = format
        }

        // MARK: - Internal methods

        package func build() throws -> [NIOSSLCertificate] {
            switch source {
            case .bytes(let bytes):
                return try [NIOSSLCertificate(bytes: bytes, format: format.build())]
            case .file(let file):
                do {
                    switch format {
                    case .der:
                        return try [NIOSSLCertificate.fromDERFile(file)]
                    case .pem:
                        return try NIOSSLCertificate.fromPEMFile(file)
                    }
                } catch {
                    throw SecureFileLoadError(resource: .certificate, path: file, underlying: error)
                }
            }
        }
    }
}
