//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    ///
    /// A `RequestTaskModifier` that answers an HTTP Digest (RFC 7616) challenge.
    ///
    /// Sets `credential` into the environment for the wrapped task, so a paired
    /// ``DigestAuthentication`` property anywhere in it reads this same instance -- see
    /// ``DigestCredential``'s own doc comment. On a `401` carrying a parseable
    /// `WWW-Authenticate: Digest` challenge, stores it on `credential` and retries, which
    /// re-resolves the whole request under that same environment, so `DigestAuthentication` now
    /// has a challenge to answer and contributes the computed `Authorization` header this time.
    /// Retries at most `maxAttempts - 1` times: if the server still answers `401` after that
    /// (wrong credentials, a challenge this package doesn't support, ...), that last response is
    /// returned as-is rather than looping.
    ///
    public struct DigestAuthentication<Input: TaskResultPrimitive>: RequestTaskModifier {

        // MARK: - Internal properties

        let credential: DigestCredential
        let maxAttempts: Int

        // MARK: - Public methods

        public func body(_ task: Content) async throws -> Input {
            var environment = task.environment
            environment.digestCredential = credential

            var attempt = 1
            var result = try await task._result(environment: environment)

            while attempt < maxAttempts,
                result.head.status.code == 401,
                let challengeHeader = result.head.headers.first(name: "WWW-Authenticate"),
                let challenge = DigestChallenge(headerValue: challengeHeader)
            {
                credential.challenge = challenge
                attempt += 1
                result = try await task._result(environment: environment)
            }

            return result
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask where Element: TaskResultPrimitive {

    ///
    /// Answers an HTTP Digest (RFC 7616) challenge for this task, retrying once with the
    /// computed `Authorization` header after a `401`.
    ///
    /// Pairs with the ``DigestAuthentication`` property, which must also be present earlier in
    /// the same request -- this modifier hands it the challenge it saw through the environment;
    /// the property is what turns it into a header on the retry. See ``DigestCredential``'s own
    /// doc comment for the shared-state contract between the two.
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
    /// - Parameters:
    ///    - credential: Defaults to a fresh, empty ``DigestCredential`` -- pass one explicitly
    ///    only to reuse a known nonce across separate requests (see its own doc comment).
    ///    - maxAttempts: How many times to send the request in total -- one initial, unauthenticated
    ///    probe plus up to `maxAttempts - 1` authenticated retries. Defaults to `2` (one probe, one
    ///    retry), which is all RFC 7616's challenge/response flow ever calls for; a higher value
    ///    only matters if the server is expected to rotate its nonce mid-flow.
    ///
    /// - Returns: The modified task, retrying once to answer a Digest challenge.
    ///
    public func digestAuthentication(
        _ credential: DigestCredential = DigestCredential(),
        maxAttempts: Int = 2
    ) -> ModifiedRequestTask<Modifiers.DigestAuthentication<Element>> {
        modifier(
            Modifiers.DigestAuthentication(
                credential: credential,
                maxAttempts: maxAttempts
            )
        )
    }
}
