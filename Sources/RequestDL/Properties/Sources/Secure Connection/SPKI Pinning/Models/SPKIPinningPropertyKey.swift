//
// See LICENSE for this package's licensing information.
//

/// Marks whether the current environment is inside an ``SPKIPinning``'s `content` closure, the
/// only context an ``SPKIHash`` has any effect in: `SPKIPinning._makeProperty` finds its pins by
/// searching its own resolved `content` subtree for `SPKIHashNode`s, not through `SPKIHash`'s own
/// `_makeProperty`, so a loose `SPKIHash` declared anywhere else silently contributes nothing.
struct SPKIPinningPropertyKey: RequestEnvironmentKey {
    static var defaultValue: Bool { false }
}

extension RequestEnvironmentValues {

    var isInsideSPKIPinning: Bool {
        get { self[SPKIPinningPropertyKey.self] }
        set { self[SPKIPinningPropertyKey.self] = newValue }
    }
}
