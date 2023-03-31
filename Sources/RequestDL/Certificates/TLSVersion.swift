/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum TLSVersion: Int {
    /// The TLS 1.0 version.
    case v1

    /// The TLS 1.1 version.
    case v1_1

    /// The TLS 1.2 version.
    case v1_2

    /// The TLS 1.3 version.
    case v1_3
}

extension TLSVersion {

    func build() -> tls_protocol_version_t {
        switch self {
        case .v1:
            return .TLSv10
        case .v1_1:
            return .TLSv11
        case .v1_2:
            return .TLSv12
        case .v1_3:
            return .TLSv13
        }
    }
}
