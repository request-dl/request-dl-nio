//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

/// Shared state between ``DigestAuthentication`` (which builds the `Authorization` header) and
/// ``RequestTask/digestAuthentication(_:maxAttempts:)`` (which parses the server's challenge and
/// drives the retry). ``RequestTask/digestAuthentication(_:maxAttempts:)`` creates one by default
/// and threads it through the environment, so most callers never construct one directly:
///
/// ```swift
/// try await DataTask {
///     BaseURL("example.com")
///     Path("secure")
///     DigestAuthentication(username: "user", password: "pass")
/// }
/// .digestAuthentication()
/// .result()
/// ```
///
/// Construct one yourself only to reuse it explicitly across separate requests, passing it to
/// ``RequestTask/digestAuthentication(_:maxAttempts:)`` in place of its default.
///
/// - Important: Reused across every request made with it: the same instance carries the
/// server's nonce from one request into the next, matching how a real Digest client is expected
/// to behave. Give unrelated requests (different hosts, different credentials) their own
/// instance.
public final class DigestCredential: @unchecked Sendable {

    // MARK: - Internal properties

    var challenge: DigestChallenge? {
        get { lock.withLock { _challenge } }
        set {
            lock.withLock {
                // A new server nonce starts its own `nc` sequence at zero; reusing the previous
                // challenge's count against a different nonce wouldn't mean anything to the
                // server. Same nonce reassigned (e.g. the identical challenge object stored
                // again) leaves the count where it was, so a caller re-setting `challenge` to
                // what it already is can't reset replay protection back to `00000001`.
                if _challenge?.nonce != newValue?.nonce {
                    _nonceCount = 0
                }
                _challenge = newValue
            }
        }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _challenge: DigestChallenge?
    private var _nonceCount: UInt32 = 0

    // MARK: - Internal methods

    /// The next `nc` (nonce-count) value for the current challenge's nonce, per RFC 7616 §3.3: a
    /// strictly increasing counter a server can use to detect a replayed/duplicated request.
    /// Every request made with this credential — including a second one that reuses the same
    /// challenge without a fresh `401`, the documented, encouraged way to reuse a
    /// ``DigestCredential`` — advances this, so the mechanism stays live instead of the request
    /// always claiming to be the nonce's first use.
    func nextNonceCount() -> String {
        lock.withLock {
            _nonceCount += 1
            let hex = String(_nonceCount, radix: 16)
            return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
        }
    }

    // MARK: - Inits

    /// Initializes an empty credential: no challenge yet, so the first request this is used
    /// with carries no `Authorization` header until the server issues one.
    public init() {}
}
