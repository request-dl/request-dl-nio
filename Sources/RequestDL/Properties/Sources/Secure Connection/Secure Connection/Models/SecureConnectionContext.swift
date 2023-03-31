/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum SecureConnectionContext {
    case server
    case client
}

extension SecureConnectionContext {

    func build() -> Internals.ConnectionContext {
        switch self {
        case .server:
            return .server
        case .client:
            return .client
        }
    }
}
