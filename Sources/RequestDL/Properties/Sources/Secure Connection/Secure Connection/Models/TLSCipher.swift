/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// Represents a TLS cipher suite.
///
/// TLSCipher defines various commonly used cipher suites for securing communication over TLS
/// (Transport Layer Security) protocol.
public struct TLSCipher: Sendable, RawRepresentable, Hashable {

    // MARK: - Public static property

    public static let TLS_RSA_WITH_AES_128_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_RSA_WITH_AES_128_CBC_SHA)
    }()

    public static let TLS_RSA_WITH_AES_256_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_RSA_WITH_AES_256_CBC_SHA)
    }()

    public static let TLS_PSK_WITH_AES_128_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_PSK_WITH_AES_128_CBC_SHA)
    }()

    public static let TLS_PSK_WITH_AES_256_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_PSK_WITH_AES_256_CBC_SHA)
    }()

    public static let TLS_RSA_WITH_AES_128_GCM_SHA256: TLSCipher = {
        TLSCipher(.TLS_RSA_WITH_AES_128_GCM_SHA256)
    }()

    public static let TLS_RSA_WITH_AES_256_GCM_SHA384: TLSCipher = {
        TLSCipher(.TLS_RSA_WITH_AES_256_GCM_SHA384)
    }()

    public static let TLS_AES_128_GCM_SHA256: TLSCipher = {
        TLSCipher(.TLS_AES_128_GCM_SHA256)
    }()

    public static let TLS_AES_256_GCM_SHA384: TLSCipher = {
        TLSCipher(.TLS_AES_256_GCM_SHA384)
    }()

    public static let TLS_CHACHA20_POLY1305_SHA256: TLSCipher = {
        TLSCipher(.TLS_CHACHA20_POLY1305_SHA256)
    }()

    public static let TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA)
    }()

    public static let TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA)
    }()

    public static let TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA)
    }()

    public static let TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA)
    }()

    public static let TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA)
    }()

    public static let TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA: TLSCipher = {
        TLSCipher(.TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA)
    }()

    public static let TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256: TLSCipher = {
        TLSCipher(.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
    }()

    public static let TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384: TLSCipher = {
        TLSCipher(.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384)
    }()

    public static let TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256: TLSCipher = {
        TLSCipher(.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256)
    }()

    public static let TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384: TLSCipher = {
        TLSCipher(.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384)
    }()

    public static let TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256: TLSCipher = {
        TLSCipher(.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256)
    }()

    public static let TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256: TLSCipher = {
        TLSCipher(.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256)
    }()

    // MARK: - Public properties

    public let rawValue: UInt16

    // MARK: - Inits

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    init(_ cipher: NIOSSL.NIOTLSCipher) {
        self.init(rawValue: cipher.rawValue)
    }

    // MARK: - Internal methods

    func build() -> NIOSSL.NIOTLSCipher {
        .init(rawValue: rawValue)
    }
}
