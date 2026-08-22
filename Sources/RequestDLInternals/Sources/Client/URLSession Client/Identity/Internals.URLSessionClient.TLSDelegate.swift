//
// See LICENSE for this package's licensing information.
//

// Phase 5e of URLSESSION_TASK.md.

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.URLSessionClient {

    /// Routes TLS challenges (server-trust, client-certificate) by host -- promoted from the
    /// URLSession Executor Spike's `RoutingMTLSURLSessionDelegate`, not the single-identity
    /// `MTLSURLSessionDelegate` the spike test itself used. One `URLSession` -- and, once Phase 6
    /// wires this client into the pooled `Internals.ClientManager` -- potentially one
    /// `URLSessionClient` can end up serving requests to many hosts, each with its own
    /// `Internals.SecureConnection`; routing by host is what keeps that from becoming a single
    /// hardcoded identity/trust policy applied indiscriminately everywhere.
    ///
    /// Today, `Internals.URLSessionClient` only ever resolves one `Internals.SecureConnection`
    /// (the one it was configured with, same as `redirectConfiguration`/`proxy`), so `policies`
    /// carries at most one entry -- keyed by whatever host the caller's request targets, not
    /// resolved eagerly at init since the client itself isn't tied to one URL. A host with no
    /// entry defers to the system's own handling, same as the spike's routing delegate: this is
    /// the routing-delegate equivalent of RequestDL's existing per-request
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
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
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
