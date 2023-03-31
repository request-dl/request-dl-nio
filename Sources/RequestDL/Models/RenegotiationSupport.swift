/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum RenegotiationSupport {

    case none

    case once

    case always
}

extension RenegotiationSupport {

    func build() -> Internals.NIORenegotiationSupport {
        switch self {
        case .none:
            return .none
        case .once:
            return .once
        case .always:
            return .always
        }
    }
}
