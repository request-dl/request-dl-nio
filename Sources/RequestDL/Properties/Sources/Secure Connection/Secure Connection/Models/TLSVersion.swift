/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOSSL

/**
 An enumeration that represents different versions of the Transport Layer Security (TLS) protocol.

 `TLSVersion` provides options to specify different versions of the TLS protocol in Swift.
 */
public enum TLSVersion: Int, Hashable, Sendable {

    /// The TLS 1.0 version.
    case v1

    /// The TLS 1.1 version.
    case v1_1

    /// The TLS 1.2 version.
    case v1_2

    /// The TLS 1.3 version.
    case v1_3
}

extension TLSVersion: Comparable {

    var downgrade: TLSVersion {
        switch self {
        case .v1, .v1_1:
            return .v1
        case .v1_2:
            return .v1_1
        case .v1_3:
            return .v1_2
        }
    }

    public static func < (_ lhs: TLSVersion, _ rhs: TLSVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension TLSVersion {

    func build() -> NIOSSL.TLSVersion {
        switch self {
        case .v1:
            return .tlsv1
        case .v1_1:
            return .tlsv11
        case .v1_2:
            return .tlsv12
        case .v1_3:
            return .tlsv13
        }
    }
}
