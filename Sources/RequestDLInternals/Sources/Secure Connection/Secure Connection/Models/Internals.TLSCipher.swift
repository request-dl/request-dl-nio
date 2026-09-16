//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.NIOTLSCipher` — a raw `UInt16` wrapper, same shape and same
    /// static members as `RequestDL.TLSCipher`.
    package struct TLSCipher: Sendable, RawRepresentable, Hashable {

        // MARK: - Internal static properties

        package static let TLS_RSA_WITH_AES_128_CBC_SHA = TLSCipher(rawValue: 0x2F)
        package static let TLS_RSA_WITH_AES_256_CBC_SHA = TLSCipher(rawValue: 0x35)
        package static let TLS_PSK_WITH_AES_128_CBC_SHA = TLSCipher(rawValue: 0x8C)
        package static let TLS_PSK_WITH_AES_256_CBC_SHA = TLSCipher(rawValue: 0x8D)
        package static let TLS_RSA_WITH_AES_128_GCM_SHA256 = TLSCipher(rawValue: 0x9C)
        package static let TLS_RSA_WITH_AES_256_GCM_SHA384 = TLSCipher(rawValue: 0x9D)
        package static let TLS_AES_128_GCM_SHA256 = TLSCipher(rawValue: 0x1301)
        package static let TLS_AES_256_GCM_SHA384 = TLSCipher(rawValue: 0x1302)
        package static let TLS_CHACHA20_POLY1305_SHA256 = TLSCipher(rawValue: 0x1303)
        package static let TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA = TLSCipher(rawValue: 0xC009)
        package static let TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA = TLSCipher(rawValue: 0xC00A)
        package static let TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA = TLSCipher(rawValue: 0xC013)
        package static let TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA = TLSCipher(rawValue: 0xC014)
        package static let TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA = TLSCipher(rawValue: 0xC035)
        package static let TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA = TLSCipher(rawValue: 0xC036)
        package static let TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 = TLSCipher(rawValue: 0xC02B)
        package static let TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 = TLSCipher(rawValue: 0xC02C)
        package static let TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 = TLSCipher(rawValue: 0xC02F)
        package static let TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 = TLSCipher(rawValue: 0xC030)
        package static let TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 = TLSCipher(rawValue: 0xCCA8)
        package static let TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 = TLSCipher(rawValue: 0xCCA9)

        // MARK: - Internal properties

        package let rawValue: UInt16

        // MARK: - Inits

        package init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> NIOSSL.NIOTLSCipher {
            .init(rawValue: rawValue)
        }
        #endif
    }
}
