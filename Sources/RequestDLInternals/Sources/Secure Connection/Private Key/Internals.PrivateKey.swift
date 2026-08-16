//
// See LICENSE for this package's licensing information.
//

import NIOSSL

extension Internals {

    package struct PrivateKey: Sendable, Equatable {

        package enum Source: Hashable {
            case file(String)
            case bytes([UInt8])
        }

        // MARK: - Internal properties

        package let source: Source
        package let format: Internals.Certificate.Format
        package let password: NIOSSLSecureBytes?

        // MARK: - Inits

        package init(_ file: String, format: Internals.Certificate.Format) {
            self.source = .file(file)
            self.format = format
            self.password = nil
        }

        package init(_ bytes: [UInt8], format: Internals.Certificate.Format) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = nil
        }

        package init(_ file: String, format: Internals.Certificate.Format, password: NIOSSLSecureBytes) {
            self.source = .file(file)
            self.format = format
            self.password = password
        }

        package init(_ bytes: [UInt8], format: Internals.Certificate.Format, password: NIOSSLSecureBytes) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = password
        }

        // MARK: - Internal methods

        package func build() throws -> NIOSSLPrivateKey {
            let format = format.build()

            switch source {
            case .bytes(let bytes):
                if let password {
                    return try .init(bytes: bytes, format: format) {
                        $0(Array(password))
                    }
                } else {
                    return try .init(bytes: bytes, format: format)
                }
            case .file(let file):
                do {
                    if let password {
                        return try .init(file: file, format: format) {
                            $0(Array(password))
                        }
                    } else {
                        return try .init(file: file, format: format)
                    }
                } catch {
                    throw SecureFileLoadError(resource: .privateKey, path: file, underlying: error)
                }
            }
        }
    }
}
