/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum SPKIHashAnchor: Sendable, Hashable {
    case active
    case backup
}

private struct SPKIHashAnchorEnvironmentKey: RequestEnvironmentKey {
    static let defaultValue: SPKIHashAnchor = .active
}

extension RequestEnvironmentValues {

    var spkiHashAnchor: SPKIHashAnchor {
        get { self[SPKIHashAnchorEnvironmentKey.self] }
        set { self[SPKIHashAnchorEnvironmentKey.self] = newValue }
    }
}
