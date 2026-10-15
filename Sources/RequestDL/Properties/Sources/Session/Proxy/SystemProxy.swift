//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// `SystemProxy` follows the proxy the operating system is configured to use.
///
/// The underlying HTTP client has no proxy discovery of its own, so by default a proxy set in
/// System Settings, in the Wi-Fi configuration of a device, or through the `http_proxy` family of
/// environment variables is ignored. Declaring this property opts a request into it.
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     SystemProxy()
/// }
/// ```
///
/// This is what makes an interception proxy such as Proxyman or Charles see the traffic, since
/// both work by installing themselves as the system proxy.
///
/// > Important: Interception proxies also re-sign TLS with their own certificate authority. The
/// TLS stack used here does not read the system keychain, so trusting the authority on the device
/// is not enough on its own: point ``TrustRoots`` at the proxy's certificate as well.
///
/// > Note: An explicit ``Proxy`` takes precedence. Declaring both leaves the explicit one in
/// effect.
///
/// > Note: Proxy auto configuration (a PAC script) is evaluated (fetched and run as JavaScript
/// against the request's URL, exactly like a browser would), with results cached briefly per
/// script/URL pair so a burst of requests to the same host doesn't re-fetch and re-evaluate the
/// same script for each one. A PAC script that's unreachable, or fails to evaluate, resolves to a
/// direct connection and a warning in the log by default, which on a network that requires a
/// proxy sends the request around it. Declare ``PACFailurePolicy/fail`` to fail the request
/// instead, with a ``ProxyAutoConfigurationError``, or use the last answer the script gave:
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     SystemProxy(onPACFailure: .fail)
/// }
///
/// DataTask {
///     BaseURL("example.com")
///     SystemProxy(onPACFailure: .lastKnown(orElse: .fail))
/// }
/// ```
public struct SystemProxy: Property {

    /// What a request does when the PAC script that decides its proxy cannot be fetched or run.
    public enum PACFailurePolicy: Sendable, Hashable {

        /// What to do when there is no last answer to fall back on.
        public enum Fallback: Sendable, Hashable {

            /// Send the request directly, and report it in the log.
            case direct

            /// Fail the request with a ``ProxyAutoConfigurationError``.
            case fail
        }

        /// Send the request directly, and report it in the log. This is the default.
        case direct

        /// Fail the request with a ``ProxyAutoConfigurationError``.
        case fail

        /// Use the last answer the script gave for this URL, and report it in the log; and when
        /// the script never answered, do what `orElse` says.
        ///
        /// The answer is kept in memory for the life of the process, so it can be old, and it is
        /// not there after a launch. A script that is down from the first request has no answer to
        /// fall back on.
        case lastKnown(orElse: Fallback)

        var internalPolicy: Internals.SystemProxyResolver.PACFailurePolicy {
            switch self {
            case .direct:
                return .direct

            case .fail:
                return .fail

            case .lastKnown(let fallback):
                switch fallback {
                case .direct:
                    return .lastKnown(orElse: .direct)

                case .fail:
                    return .lastKnown(orElse: .fail)
                }
            }
        }
    }

    private struct Node: PropertyNode {

        let pac: Internals.SystemProxyResolver.PACOptions

        func make(_ make: inout Make) async throws {
            // Only a request, not a resolution. Which proxy the system would use depends on the
            // URL, and the URL is only complete once every property has had its turn, so the
            // answer is looked up at the end of the build rather than here.
            make.resolvesSystemProxy = true
            make.systemProxyPAC = pac
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let pac: Internals.SystemProxyResolver.PACOptions

    // MARK: - Inits

    /// Initializes a new instance that follows the system's proxy configuration.
    public init() {
        self.pac = .init()
    }

    /// Initializes a new instance that follows the system's proxy configuration.
    ///
    /// - Parameters:
    ///   - onPACFailure: What to do when the system's proxy is a PAC script that cannot be
    ///   fetched or run.
    ///   - evaluationTimeout: How long fetching and running a PAC script may take. 30 seconds by
    ///   default, because a script is often hosted on a slow internal server. A request that
    ///   arrives while another one is already evaluating the same script waits for that
    ///   evaluation, and so for its timeout. A timeout of zero or less makes every evaluation fail
    ///   at once.
    ///   - failureLifetime: How long a failure is remembered. Until it passes, requests do not ask
    ///   the script again: they get the failure, at once, instead of each waiting out the
    ///   evaluation. 10 seconds by default. Zero or less remembers nothing, and every request
    ///   asks the script itself.
    public init(
        onPACFailure: PACFailurePolicy,
        evaluationTimeout: UnitTime = .seconds(30),
        failureLifetime: UnitTime = .seconds(10)
    ) {
        self.pac = .init(
            onFailure: onPACFailure.internalPolicy,
            evaluationTimeout: Double(max(evaluationTimeout.nanoseconds, 0)) / 1_000_000_000,
            failureLifetime: max(failureLifetime.nanoseconds, 0)
        )
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SystemProxy>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(pac: property.pac))
    }
}
