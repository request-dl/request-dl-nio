//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.URLSessionClient {

    /// Routes a TLS challenge (server-trust, client-certificate) to `policy`.
    ///
    /// `Internals.URLSessionClient` only ever resolves one `Internals.SecureConnection` (the one
    /// it was configured with, same as `redirectConfiguration`/`proxy`), so there is only ever one
    /// `Internals.URLSessionIdentityPolicy` to route to, not a per-host map of them. What varies
    /// per request is what the delegate answers for: `execute(...)` builds a fresh `TLSDelegate`
    /// for each request, after recording the request's destination host and port among the
    /// client's origins, since the client itself isn't tied to a single URL.
    ///
    /// `origins` (host and port, recorded by `execute`; the rule `.nio` follows too: see
    /// `Internals.IdentityOrigins`) still reaches
    /// `policy.handle(challenge:isConfiguredHost:completionHandler:)`, but only gates whether a
    /// client-certificate credential is presented. Server-trust challenges
    /// (pinning, custom trust roots, revocation, hostname-verification overrides) are always
    /// routed to `policy` regardless of host: a redirect target this policy was never configured
    /// for still has to be checked against that same trust configuration, since a redirect is
    /// exactly the kind of thing pinning needs to survive, not a reason to fall back to bare
    /// system trust. See `URLSessionIdentityPolicy.handle`'s own doc comment.
    final class TLSDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

        // MARK: - Private properties

        private let origins: Internals.IdentityOrigins
        private let policy: Internals.URLSessionIdentityPolicy

        // MARK: - Inits

        init(origins: Internals.IdentityOrigins, policy: Internals.URLSessionIdentityPolicy) {
            self.origins = origins
            self.policy = policy
        }

        // MARK: - Internal properties

        /// Whether a challenge from `protectionSpace` is from an origin a request was made to
        /// with this client, which is the only kind the client identity is presented to. A
        /// redirect to another host, or to another port of the same host, is not.
        func isConfiguredOrigin(_ protectionSpace: URLProtectionSpace) -> Bool {
            origins.contains(host: protectionSpace.host, port: protectionSpace.port)
        }

        // MARK: - Internal methods

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            policy.handle(
                challenge: challenge,
                isConfiguredHost: isConfiguredOrigin(challenge.protectionSpace),
                completionHandler: completionHandler
            )
        }
    }
}

#endif
