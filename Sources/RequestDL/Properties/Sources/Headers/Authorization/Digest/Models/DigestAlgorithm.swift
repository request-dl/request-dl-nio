//
// See LICENSE for this package's licensing information.
//

import Crypto

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// The hash algorithm a Digest challenge asked for, per RFC 7616 §6.1.
enum DigestAlgorithm: Sendable, Hashable {

    case md5
    case md5Sess
    case sha256
    case sha256Sess

    // MARK: - Inits

    /// - Parameter rawValue: The challenge's `algorithm` parameter, or `nil` when absent --
    /// which RFC 7616 §3.3 says implies `MD5`, the same default RFC 2069 always assumed.
    init?(rawValue: String?) {
        switch rawValue?.uppercased() {
        case nil, "MD5":
            self = .md5
        case "MD5-SESS":
            self = .md5Sess
        case "SHA-256":
            self = .sha256
        case "SHA-256-SESS":
            self = .sha256Sess
        default:
            return nil
        }
    }

    // MARK: - Internal properties

    /// Whether this is a `-sess` variant, which folds a client/server nonce pair into `HA1`
    /// itself rather than recomputing it fresh for every request. Not currently supported by
    /// ``DigestAuthentication`` -- see its own doc comment.
    var isSession: Bool {
        switch self {
        case .md5Sess, .sha256Sess:
            return true
        case .md5, .sha256:
            return false
        }
    }

    /// The wire value for the `algorithm` parameter on the outgoing `Authorization` header.
    var headerValue: String {
        switch self {
        case .md5: return "MD5"
        case .md5Sess: return "MD5-sess"
        case .sha256: return "SHA-256"
        case .sha256Sess: return "SHA-256-sess"
        }
    }

    // MARK: - Internal methods

    /// Hex-encoded digest of `string`, per RFC 7616 §3.4.2 (`H(data) = hex(hash(data))`).
    func hexDigest(_ string: String) -> String {
        let data = Data(string.utf8)

        switch self {
        case .md5, .md5Sess:
            return Insecure.MD5.hash(data: data).hexEncoded
        case .sha256, .sha256Sess:
            return SHA256.hash(data: data).hexEncoded
        }
    }
}

// MARK: - Digest hex encoding

extension Sequence where Element == UInt8 {

    var hexEncoded: String {
        map {
            let hex = String($0, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }
        .joined()
    }
}
