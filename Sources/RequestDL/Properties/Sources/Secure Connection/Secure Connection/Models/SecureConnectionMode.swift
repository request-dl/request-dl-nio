//
// See LICENSE for this package's licensing information.
//

/// How a ``SecureConnection`` treats the secure connection configuration declared outside of it.
///
/// ``SecureConnection`` wraps the settings that live directly on it (`version`, `cipherSuites`,
/// `verification`, ...), but the properties that don't need it (``SPKIPinning``, ``TrustRoots``,
/// ``Certificates``, ``PrivateKey``, ...) can also be declared on their own, next to it. This
/// type says what happens when both are present, the same way ``HeaderStrategy`` does for
/// headers: ``merging`` is the default, ``override`` the explicit opt-in.
///
/// ```swift
/// DataTask {
///     BaseURL("api.example.com")
///
///     SPKIPinning {
///         SPKIHash("base64-encoded-active-pin")
///     }
///
///     // Keeps the pins above and only adds the TLS version on top of them.
///     SecureConnection()
///         .version(minimum: .v1_3)
///
///     // Starts over: the pins above, and everything else declared before it, are discarded.
///     SecureConnection(.override)
///         .version(minimum: .v1_3)
/// }
/// ```
public enum SecureConnectionMode: Sendable, Hashable {

    /// The ``SecureConnection`` starts from the configuration declared before it and applies only
    /// what it configures itself on top, so everything it doesn't mention is kept, pins included,
    /// and what it does configure wins over the same setting declared before. This is the
    /// default.
    case merging

    /// The ``SecureConnection`` is the whole configuration: whatever was declared outside of it,
    /// before it, is replaced by what it configures itself, silently. This is what
    /// ``SecureConnection`` always did before ``merging`` became the default.
    case override
}
