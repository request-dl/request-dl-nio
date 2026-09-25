//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    package struct PrivateKey: Sendable, Equatable {

        package enum Source: Hashable {
            case file(String)
            case bytes([UInt8])
        }

        // MARK: - Internal properties

        package let source: Source
        package let format: Internals.Certificate.Format
        package let password: SecureBytes?

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

        package init(_ file: String, format: Internals.Certificate.Format, password: SecureBytes) {
            self.source = .file(file)
            self.format = format
            self.password = password
        }

        package init(_ bytes: [UInt8], format: Internals.Certificate.Format, password: SecureBytes) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = password
        }

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() throws -> NIOSSLPrivateKey {
            let format = format.build()

            switch source {
            case .bytes(let bytes):
                if let password {
                    // `NIOSSLPassphraseCallback`/`NIOSSLPassphraseSetter` are generic over any
                    // `Collection<UInt8>`, not hardcoded to `[UInt8]` -- and `SecureBytes` already
                    // conforms to `RandomAccessCollection` with `Element == UInt8` -- so this can
                    // hand NIOSSL `password` directly instead of first copying it into a plain
                    // `Array`, which (unlike `SecureBytes`/`ZeroingBytes`) has no zeroing
                    // guarantee of its own and would sit in memory unzeroed after use, for
                    // however long ARC takes to release it.
                    return try .init(bytes: bytes, format: format) {
                        $0(password)
                    }
                } else {
                    return try .init(bytes: bytes, format: format)
                }
            case .file(let file):
                do {
                    if let password {
                        return try .init(file: file, format: format) {
                            $0(password)
                        }
                    } else {
                        return try .init(file: file, format: format)
                    }
                } catch {
                    throw SecureFileLoadError(resource: .privateKey, path: file, underlying: error)
                }
            }
        }
        #endif
    }
}
