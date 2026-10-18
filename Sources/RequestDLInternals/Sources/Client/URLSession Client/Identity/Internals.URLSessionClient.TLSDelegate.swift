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
    /// per request is the origin: `execute(...)` builds a fresh `TLSDelegate` for each request,
    /// pairing that one policy with the request's own destination host and port, since the client
    /// itself isn't tied to a single URL.
    ///
    /// `origin` (host and port, the rule `.nio` follows too: see `Internals.IdentityOrigin`) still
    /// reaches `policy.handle(challenge:isConfiguredHost:completionHandler:)`, but only gates
    /// whether a client-certificate credential is presented. Server-trust challenges
    /// (pinning, custom trust roots, revocation, hostname-verification overrides) are always
    /// routed to `policy` regardless of host: a redirect target this policy was never configured
    /// for still has to be checked against that same trust configuration, since a redirect is
    /// exactly the kind of thing pinning needs to survive, not a reason to fall back to bare
    /// system trust. See `URLSessionIdentityPolicy.handle`'s own doc comment.
    final class TLSDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

        // MARK: - Private properties

        private let origin: Internals.IdentityOrigin
        private let policy: Internals.URLSessionIdentityPolicy

        // MARK: - Inits

        init(origin: Internals.IdentityOrigin, policy: Internals.URLSessionIdentityPolicy) {
            self.origin = origin
            self.policy = policy
        }

        // MARK: - Internal properties

        /// Whether a challenge from `protectionSpace` is from the origin this request was made
        /// to, which is the only one the client identity is presented to. A redirect to another
        /// host, or to another port of the same host, is not.
        func isConfiguredOrigin(_ protectionSpace: URLProtectionSpace) -> Bool {
            Internals.IdentityOrigin(host: protectionSpace.host, port: protectionSpace.port) == origin
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
