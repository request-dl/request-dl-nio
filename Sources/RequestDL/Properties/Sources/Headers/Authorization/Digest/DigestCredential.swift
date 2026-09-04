//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

/// Shared state between ``DigestAuthentication`` (which builds the `Authorization` header) and
/// ``RequestTask/digestAuthentication(_:maxAttempts:)`` (which parses the server's challenge and
/// drives the retry). Create one instance and pass it to both.
///
/// ```swift
/// let credential = DigestCredential()
///
/// try await DataTask {
///     BaseURL("example.com")
///     Path("secure")
///     DigestAuthentication(credential, username: "user", password: "pass")
/// }
/// .digestAuthentication(credential)
/// .result()
/// ```
///
/// - Important: Reused across every request made with it -- the same instance carries the
/// server's nonce from one request into the next, matching how a real Digest client is expected
/// to behave. Give unrelated requests (different hosts, different credentials) their own
/// instance.
public final class DigestCredential: @unchecked Sendable {

    // MARK: - Internal properties

    var challenge: DigestChallenge? {
        get { lock.withLock { _challenge } }
        set { lock.withLock { _challenge = newValue } }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _challenge: DigestChallenge?

    // MARK: - Inits

    /// Initializes an empty credential -- no challenge yet, so the first request this is used
    /// with carries no `Authorization` header until the server issues one.
    public init() {}
}
