//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Represents a secure connection with various configuration options.
///
/// A `SecureConnection` builds on top of the secure connection configuration declared before it
/// (``SecureConnectionMode/merging``, the default): ``SPKIPinning``, ``TrustRoots``,
/// ``Certificates``, ``PrivateKey`` and the rest are kept, and only what the `SecureConnection`
/// itself configures is applied over them, winning over what was there.
///
/// ```swift
/// DataTask {
///     SPKIPinning {
///         SPKIHash("base64-encoded-active-pin")
///     }
///
///     // The pins stay; only the minimum TLS version is added.
///     SecureConnection()
///         .version(minimum: .v1_3)
/// }
/// ```
///
/// Pass ``SecureConnectionMode/override`` to start from a blank configuration instead, discarding
/// whatever was declared before it. That is what `SecureConnection` did before ``merging`` became
/// the default.
///
/// > Important: Behavior change. A `SecureConnection` used to replace everything declared before
/// it, silently dropping, for example, an ``SPKIPinning`` or a ``TrustRoots``. If you relied on
/// that reset, write `SecureConnection(.override)`.
///
/// > Note: ``TrustRoots``, ``Certificates``, ``AdditionalTrustRoots``, ``PrivateKey``,
/// ``PSKIdentity``, and ``DefaultTrustRoots`` don't require nesting inside a `SecureConnection`:
/// each creates the underlying secure connection configuration on its own the first time it's
/// needed. Nest them here only when also configuring settings that live directly on
/// `SecureConnection` (`version`, `cipherSuites`, `keyLogger`, ...).
///
/// > Important: `URLSessionConfiguration` has no API for TLS version or ALPN policy.
/// `version(maximum:)` and ``applicationProtocols(_:)`` are treated as incompatible with
/// ``Session/Executor/urlSession``, like `cipherSuites(_:)`: automatic executor resolution skips
/// `.urlSession` when either is set, and pinning to it throws ``ExecutorRequirementError``.
/// `version(minimum:)` is the one exception: it has no effect under `.urlSession` but isn't
/// flagged, because App Transport Security offers a real equivalent, an
/// `NSExceptionMinimumTLSVersion` entry in your app's `Info.plist`, that `version(maximum:)` and
/// ``applicationProtocols(_:)`` don't have. See
/// <doc:Configuring-App-Transport-Security-for-URLSession>. To control HTTP/2 use
/// ``Session/httpVersion(_:)``, which replaces ``applicationProtocols(_:)``.
public struct SecureConnection<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {

        let mode: SecureConnectionMode
        let edits: [@Sendable (inout Internals.SecureConnection) -> Void]
        let nodes: [LeafNode<SecureConnectionNode>]

        // Conforms to `SecureConnectionPropertyNode` (rather than mutating `Make` directly) so
        // that `_makeProperty` can wrap it in a `SecureConnectionNode`, the same leaf type this
        // node itself searches for and the same one every other secure connection property
        // (`TrustRoots`, `Certificates`, `PrivateKey`, ...) wraps itself in. Without that, a
        // `SecureConnection` nested inside another `SecureConnection` (via its own
        // `.leaf(Node(...))` collapsing everything into a private wrapper type) would be
        // invisible to the outer one's search, and every certificate/trust root/TLS setting it
        // configured would be silently dropped.
        //
        // Mirrors, synchronously, the exact sequence the top-level path already runs: pick the
        // base (what's already configured for `.merging`, blank for `.override`), apply the
        // wrapper's own settings on top of it, then apply each found `SecureConnectionNode` via
        // its own fresh collector. The settings are kept as edits rather than as a finished
        // `Internals.SecureConnection` so that `.merging` only touches what the wrapper actually
        // configured, instead of overwriting the base with the defaults of everything it didn't.
        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            if mode == .override {
                secureConnection = .init()
            }

            for edit in edits {
                edit(&secureConnection)
            }

            for node in nodes {
                var collector = secureConnection.collector()
                try node.passthrough(&collector)
                secureConnection = collector(\.self)
            }
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: Content

    private let mode: SecureConnectionMode

    private var edits: [@Sendable (inout Internals.SecureConnection) -> Void]

    // MARK: - Inits

    /// Initializes a secure connection with the given content.
    ///
    /// The secure connection builds on top of what was configured outside of it. See
    /// ``SecureConnectionMode/merging``.
    ///
    /// - Parameter content: A closure that provides the content of the secure connection.
    public init(
        @PropertyBuilder content: () -> Content
    ) {
        self.init(.merging, content: content)
    }

    /// Initializes a secure connection with the given content and mode.
    ///
    /// - Parameters:
    ///   - mode: Whether it builds on top of (``SecureConnectionMode/merging``, what the
    ///   initializers without a mode do) or replaces (``SecureConnectionMode/override``) the
    ///   configuration declared outside of it.
    ///   - content: A closure that provides the content of the secure connection.
    public init(
        _ mode: SecureConnectionMode,
        @PropertyBuilder content: () -> Content
    ) {
        self.mode = mode
        self.edits = []
        self.content = content()
    }

    /// Initializes a secure connection with no additional content, for chaining its fluent
    /// modifiers directly, the same way `Session()` is used. It builds on top of what was
    /// configured outside of it, like ``init(content:)``.
    ///
    /// ```swift
    /// DataTask {
    ///     BaseURL("apple.com")
    ///
    ///     SecureConnection()
    ///         .version(minimum: .v1_3)
    ///
    ///     TrustRoots {
    ///         Certificate(rootPath, format: .der)
    ///     }
    /// }
    /// ```
    public init() where Content == EmptyProperty {
        self.init {}
    }

    /// Initializes a secure connection with no additional content and the given mode.
    ///
    /// ```swift
    /// DataTask {
    ///     BaseURL("apple.com")
    ///
    ///     SPKIPinning {
    ///         SPKIHash("base64-encoded-active-pin")
    ///     }
    ///
    ///     // Starts from a blank configuration: the pins above are not applied.
    ///     SecureConnection(.override)
    ///         .version(minimum: .v1_3)
    /// }
    /// ```
    ///
    /// - Parameter mode: Whether it builds on top of (``SecureConnectionMode/merging``) or
    /// replaces (``SecureConnectionMode/override``) the configuration declared outside of it.
    public init(_ mode: SecureConnectionMode) where Content == EmptyProperty {
        self.init(mode) {}
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SecureConnection<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .leaf(
            SecureConnectionNode(
                Node(
                    mode: property.mode,
                    edits: property.edits,
                    nodes: outputs.node.search(for: SecureConnectionNode.self)
                ),
                logger: inputs.environment.logger
            )
        )
    }

    // MARK: - Public methods

    /// Sets the minimum TLS version for the secure connection.
    ///
    /// Without it, the ``Session/Executor/nio`` executors refuse anything below TLS 1.2. Pass
    /// `.v1` or `.v1_1` to connect to a server that still speaks one of those.
    ///
    /// > Important: Has no effect under ``Session/Executor/urlSession``. Configure an
    /// `NSExceptionMinimumTLSVersion` ATS exception in `Info.plist` instead. See
    /// <doc:Configuring-App-Transport-Security-for-URLSession>.
    ///
    /// - Parameter minimum: The minimum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the minimum TLS version set.
    public func version(minimum: TLSVersion) -> Self {
        let version = minimum.build()
        return configure { $0.minimumTLSVersion = version }
    }

    #if canImport(NIOCore)
    /// Sets the maximum TLS version for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: `URLSessionConfiguration` has no
    /// maximum-TLS-version API, and App Transport Security has no `Info.plist` key for one
    /// either, so there is no executor left this could ever take effect on. In a build where NIO
    /// is available, this is treated as incompatible with ``Session/Executor/urlSession``:
    /// automatic executor resolution skips it in favor of a NIO-based executor, and pinning to
    /// `.urlSession` via ``Session/requiredExecutor(_:)`` throws ``ExecutorRequirementError``. See
    /// <doc:Configuring-App-Transport-Security-for-URLSession>.
    ///
    /// - Parameter maximum: The maximum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the maximum TLS version set.
    public func version(maximum: TLSVersion) -> Self {
        let version = maximum.build()
        return configure { $0.maximumTLSVersion = version }
    }

    /// Sets the minimum and maximum TLS versions for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO. See ``version(maximum:)``. Use
    /// ``version(minimum:)`` alone there instead.
    ///
    /// - Parameters:
    ///   - minimum: The minimum TLS version to use.
    ///   - maximum: The maximum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the minimum and maximum TLS versions set.
    public func version(minimum: TLSVersion, maximum: TLSVersion) -> Self {
        version(minimum: minimum).version(maximum: maximum)
    }

    /// Sets the TLS version range for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO. See ``version(maximum:)``. Use
    /// ``version(minimum:)`` alone there instead.
    ///
    /// - Parameter range: The range of TLS versions to use.
    /// - Returns: A modified `SecureConnection` with the TLS version range set.
    public func version(_ range: Range<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound.downgrade
        )
    }

    /// Sets the TLS version range for the secure connection, inclusive of both ends.
    ///
    /// - Important: Unavailable in a build without NIO. See ``version(maximum:)``. Use
    /// ``version(minimum:)`` alone there instead.
    ///
    /// - Parameter range: The closed range of TLS versions to use.
    /// - Returns: A modified `SecureConnection` with the TLS version range set.
    public func version(_ range: ClosedRange<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound
        )
    }

    /// Sets the key log object for the secure connection.
    ///
    /// - Important: Reachable under ``Session/Executor/nio`` only. This is a **permanent**
    /// limitation of the underlying platforms, not a gap awaiting a fix. Neither Network.framework
    /// nor `URLSession` exposes any public API for observing per-session TLS secrets, which is
    /// also why this method, and ``SSLKeyLogger`` itself, don't exist at all in a build without
    /// NIO.
    ///
    /// ``Session/requiredExecutor(_:)``/``Session/preferredExecutor(_:)`` steer a session with a
    /// key logger configured away from both ``Session/Executor/nioTransportServices`` and
    /// ``Session/Executor/urlSession``. Letting that combination reach the OS layer at all would
    /// crash the process outright under Network.framework.
    ///
    /// - Parameter keyLogger: The `SSLKeyLogger` object.
    /// - Returns: A modified `SecureConnection` with the key logger set.
    public func keyLogger(_ keyLogger: SSLKeyLogger) -> Self {
        configure {
            $0.keyLogger = keyLogger
        }
    }

    /// Sets the timeout for shutting down the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: NIOSSL is what shuts down, so there's
    /// nothing for this to configure there.
    ///
    /// - Parameter timeout: The timeout for shutting down the secure connection. It must not be
    ///   negative: that is a mistake in the code that wrote it, and traps, like a negative
    ///   ``Timeout``.
    /// - Returns: A modified `SecureConnection` with the shutdown timeout set.
    public func shutdownTimeout(_ timeout: UnitTime) -> Self {
        precondition(
            timeout >= .zero,
            "shutdownTimeout cannot be negative, got \(timeout.nanoseconds) nanoseconds."
        )

        return configure { $0.shutdownTimeout = timeout.nanoseconds }
    }

    /// Sets the renegotiation support for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: TLS renegotiation is a NIOSSL-specific
    /// concept with no Network.framework/URLSession equivalent.
    ///
    /// - Parameter renegotiationSupport: The renegotiation support setting.
    /// - Returns: A modified `SecureConnection` with the renegotiation support set.
    public func renegotiationSupport(_ renegotiationSupport: RenegotiationSupport) -> Self {
        configure { $0.renegotiationSupport = renegotiationSupport.build() }
    }

    /// Sets the signing signature algorithms for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: neither Network.framework nor
    /// `URLSession` exposes a signing-signature-algorithm restriction API.
    ///
    /// - Parameter algorithm: The signature algorithms to use for signing.
    /// - Returns: A modified `SecureConnection` with the signing signature algorithms set.
    public func signingSignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        configure {
            $0.signingSignatureAlgorithms = algorithm.map {
                $0.build()
            }
        }
    }

    /// Sets the verify signature algorithms for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO. See
    /// ``signingSignatureAlgorithms(_:)``.
    ///
    /// - Parameter algorithm: The signature algorithms to use for verification.
    /// - Returns: A modified `SecureConnection` with the verify signature algorithms set.
    public func verifySignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        configure {
            $0.verifySignatureAlgorithms = algorithm.map {
                $0.build()
            }
        }
    }
    #endif

    /// Sets the certificate verification setting for the secure connection.
    ///
    /// - Parameter verification: The certificate verification setting.
    /// - Returns: A modified `SecureConnection` with the certificate verification setting set.
    public func verification(_ verification: CertificateVerification) -> Self {
        configure { $0.certificateVerification = verification.build() }
    }

    /// Sets the revocation-checking policy for the secure connection.
    ///
    /// - Important: Reachable on Apple platforms only (``Session/Executor/nio``,
    /// ``Session/Executor/nioTransportServices``, ``Session/Executor/urlSession``). NIOSSL/
    /// BoringSSL implements no revocation checking of its own, so this has no effect at all on
    /// Linux.
    ///
    /// - Parameter policy: The revocation-checking policy to use.
    /// - Returns: A modified `SecureConnection` with the revocation policy set.
    public func revocationPolicy(_ policy: RevocationPolicy) -> Self {
        configure { $0.revocationPolicy = policy.build() }
    }

    /// Sets an observer that's notified of each TLS trust-evaluation decision this secure
    /// connection makes, for observability or security-audit logging, purely informational.
    ///
    /// - Important: See ``TrustDecisionObserver``'s own doc comment for exactly when this fires
    /// under each executor; it's not every connection.
    ///
    /// - Parameter observer: The observer to notify of each trust decision.
    /// - Returns: A modified `SecureConnection` with the trust decision observer set.
    public func trustDecisionObserver(_ observer: TrustDecisionObserver) -> Self {
        configure { $0.trustDecisionObserver = observer }
    }

    #if canImport(NIOCore)
    /// Sets the application protocols for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: `URLSession` negotiates ALPN
    /// automatically and `Info.plist` has no key to override it, so there is no executor left
    /// this could ever take effect on. In a build where NIO is available, this is treated as
    /// incompatible with ``Session/Executor/urlSession``: automatic executor resolution skips it
    /// in favor of a NIO-based executor, and pinning to `.urlSession` via
    /// ``Session/requiredExecutor(_:)`` throws ``ExecutorRequirementError``. See
    /// <doc:Configuring-App-Transport-Security-for-URLSession>.
    ///
    /// - Note: Deprecated in favor of ``Session/httpVersion(_:)``. AsyncHTTPClient replaces the
    /// ALPN list of every HTTPS connection with `["h2", "http/1.1"]` or `["http/1.1"]`, depending
    /// only on the session's HTTP version, so the list set here never reaches the handshake.
    /// Existing callers keep compiling and keep their `.urlSession` incompatibility; use
    /// `Session().httpVersion(.http1Only)` to keep a session off HTTP/2.
    ///
    /// - Parameter protocols: The application protocols to use.
    /// - Returns: A modified `SecureConnection` with the application protocols set.
    @available(
        *,
        deprecated,
        message:
            "Use Session.httpVersion(_:) instead. The ALPN list set here is replaced by the one the session's HTTP version dictates."
    )
    public func applicationProtocols(_ protocols: String...) -> Self {
        configure { $0.applicationProtocols = protocols }
    }

    /// Disables or enables sending the CA name list during handshake for the secure connection.
    ///
    /// - Important: Unavailable in a build without NIO: this is a NIOSSL handshake detail with
    /// no Network.framework/URLSession equivalent.
    ///
    /// - Parameter isDisabled: A boolean value indicating whether to disable or enable sending the CA name list.
    /// - Returns: A modified `SecureConnection` with the CA name list setting set.
    public func sendCANameListDisabled(_ isDisabled: Bool) -> Self {
        configure { $0.sendCANameList = !isDisabled }
    }

    /// Sets the cipher suites for the secure connection using string representations.
    ///
    /// - Important: Unavailable in a build without NIO: `URLSessionConfiguration` has no cipher
    /// suite list API, so there is no executor left this could ever take effect on. In a build
    /// where NIO is available, this is treated as incompatible with ``Session/Executor/urlSession``:
    /// automatic executor resolution skips it in favor of a NIO-based executor, and pinning to
    /// `.urlSession` via ``Session/requiredExecutor(_:)`` throws ``ExecutorRequirementError``
    /// instead of silently dropping it.
    ///
    /// - Parameter suites: The cipher suites to use as string representations.
    /// - Returns: A modified `SecureConnection` with the cipher suites set.
    public func cipherSuites(_ suites: String...) -> Self {
        for suite in suites {
            precondition(!suite.contains(":"))
        }
        return configure { $0.cipherSuites = suites.joined(separator: ":") }
    }

    /// Sets the cipher suites for the secure connection using `TLSCipher` values.
    ///
    /// - Important: Unavailable in a build without NIO, for the same reason as the `String`-based
    /// `cipherSuites(_:)` overload above.
    ///
    /// - Parameter suites: The cipher suites to use as `TLSCipher` values.
    /// - Returns: A modified `SecureConnection` with the cipher suites set.
    public func cipherSuites(_ suites: TLSCipher...) -> Self {
        configure {
            $0.cipherSuiteValues = suites.map {
                $0.build()
            }
        }
    }
    #endif

    // MARK: - Internal methods

    func configure(
        _ apply: @escaping @Sendable (inout Internals.SecureConnection) -> Void
    ) -> Self {
        var mutableSelf = self
        mutableSelf.edits.append(apply)
        return mutableSelf
    }
}
