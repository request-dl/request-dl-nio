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

    /// Routes a TLS challenge (server-trust, client-certificate) to `policy` only when it's for
    /// `host` -- promoted from the URLSession Executor Spike's `RoutingMTLSURLSessionDelegate`,
    /// not the single-identity `MTLSURLSessionDelegate` the spike test itself used. One
    /// `URLSession` -- and so one `URLSessionClient`, pooled by `Internals.ClientManager` --
    /// genuinely does end up serving requests to many hosts; the host check is what keeps a
    /// challenge for one host from being answered with a policy meant for another.
    ///
    /// `Internals.URLSessionClient` only ever resolves one `Internals.SecureConnection` (the one
    /// it was configured with, same as `redirectConfiguration`/`proxy`), so there is only ever one
    /// `Internals.URLSessionIdentityPolicy` to route to -- not a per-host map of them. What varies
    /// per request is `host`: `execute(...)` builds a fresh `TLSDelegate` for each request, pairing
    /// that one policy with the request's own destination host, since the client itself isn't tied
    /// to a single URL. A challenge for any other host (mid-redirect to a different host, for
    /// instance) falls through to the system's own handling, same as the spike's routing delegate:
    /// this is the routing-delegate equivalent of RequestDL's existing per-request
    /// `Internals.SecureConnection?` already being optional.
    final class TLSDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

        // MARK: - Private properties

        private let host: String
        private let policy: Internals.URLSessionIdentityPolicy

        // MARK: - Inits

        init(host: String, policy: Internals.URLSessionIdentityPolicy) {
            self.host = host
            self.policy = policy
        }

        // MARK: - Internal methods

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.host == host else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            policy.handle(challenge: challenge, completionHandler: completionHandler)
        }
    }
}

#endif
