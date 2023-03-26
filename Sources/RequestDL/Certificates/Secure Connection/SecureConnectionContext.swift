/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public enum SecureConnectionContext {
    case server
    case client
}

extension SecureConnectionContext {

    func build() -> RequestDLInternals.Session.ConnectionContext {
        switch self {
        case .server:
            return .server
        case .client:
            return .client
        }
    }
}
