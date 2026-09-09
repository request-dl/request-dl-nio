//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// How strictly a peer certificate's revocation status (OCSP/CRL) is checked during the TLS
/// handshake.
///
/// - Important: Reachable under ``Session/Executor/nio``, ``Session/Executor/nioTransportServices``,
/// and ``Session/Executor/urlSession`` on Apple platforms only -- NIOSSL/BoringSSL implements no
/// revocation checking of its own, so setting this has no effect at all on Linux.
public enum RevocationPolicy: Sendable, Hashable {

    /// Requires a definitive, verified positive response from OCSP or CRL before trusting the
    /// certificate -- fails the handshake outright if that can't be obtained, including when the
    /// revocation responder is simply unreachable.
    case strict

    /// Skips network-based revocation checking (OCSP/CRL fetches) entirely, consulting only
    /// locally cached responses if any -- never fails a handshake over revocation status.
    ///
    /// - Warning: Also disallows network access for intermediate CA issuer (AIA) fetching, not
    /// only revocation checking itself -- a chain that depends on that to complete may fail to
    /// validate at all under this policy, independent of revocation status.
    case disabled

    // MARK: - Internal methods

    func build() -> Internals.RevocationPolicy {
        switch self {
        case .strict:
            return .strict
        case .disabled:
            return .disabled
        }
    }
}
