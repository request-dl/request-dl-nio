/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum TLSVersion: Int {
    case v1
    case v1_1
    case v1_2
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

    func build() -> Internals.TLSVersion {
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