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
/// instead, with a ``ProxyAutoConfigurationError``:
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     SystemProxy(onPACFailure: .fail)
/// }
/// ```
public struct SystemProxy: Property {

    /// What a request does when the PAC script that decides its proxy cannot be fetched or run.
    public enum PACFailurePolicy: Sendable, Hashable {

        /// Send the request directly, and report it in the log. This is the default.
        case direct

        /// Fail the request with a ``ProxyAutoConfigurationError``.
        case fail

        var internalPolicy: Internals.SystemProxyResolver.PACFailurePolicy {
            switch self {
            case .direct:
                return .direct

            case .fail:
                return .fail
            }
        }
    }

    private struct Node: PropertyNode {

        let onPACFailure: PACFailurePolicy

        func make(_ make: inout Make) async throws {
            // Only a request, not a resolution. Which proxy the system would use depends on the
            // URL, and the URL is only complete once every property has had its turn, so the
            // answer is looked up at the end of the build rather than here.
            make.resolvesSystemProxy = true
            make.systemProxyPACFailure = onPACFailure.internalPolicy
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let onPACFailure: PACFailurePolicy

    // MARK: - Inits

    /// Initializes a new instance that follows the system's proxy configuration.
    public init() {
        self.onPACFailure = .direct
    }

    /// Initializes a new instance that follows the system's proxy configuration.
    ///
    /// - Parameter onPACFailure: What to do when the system's proxy is a PAC script that cannot be
    /// fetched or run.
    public init(onPACFailure: PACFailurePolicy) {
        self.onPACFailure = onPACFailure
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SystemProxy>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(onPACFailure: property.onPACFailure))
    }
}
