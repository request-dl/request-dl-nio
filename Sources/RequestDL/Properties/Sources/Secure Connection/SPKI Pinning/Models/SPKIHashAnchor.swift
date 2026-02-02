/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum SPKIHashAnchor: Sendable, Hashable {
    case primary
    case backup
}

private struct SPKIHashAnchorEnvironmentKey: RequestEnvironmentKey {
    static let defaultValue: SPKIHashAnchor = .primary
}

extension RequestEnvironmentValues {

    var spkiHashAnchor: SPKIHashAnchor {
        get { self[SPKIHashAnchorEnvironmentKey.self] }
        set { self[SPKIHashAnchorEnvironmentKey.self] = newValue }
    }
}
