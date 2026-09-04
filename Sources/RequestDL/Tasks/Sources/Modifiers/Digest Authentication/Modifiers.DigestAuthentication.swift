//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    ///
    /// A `RequestTaskModifier` that answers an HTTP Digest (RFC 7616) challenge.
    ///
    /// On a `401` carrying a parseable `WWW-Authenticate: Digest` challenge, stores it on
    /// `credential` and retries -- which re-resolves the whole request, so a paired
    /// ``DigestAuthentication`` property earlier in the tree now has a challenge to answer and
    /// contributes the computed `Authorization` header this time. Retries at most once: if the
    /// server still answers `401` after that (wrong credentials, a challenge this package doesn't
    /// support, ...), that second response is returned as-is rather than looping.
    ///
    public struct DigestAuthentication<Input: TaskResultPrimitive>: RequestTaskModifier {

        // MARK: - Internal properties

        let credential: DigestCredential
        let maxAttempts: Int

        // MARK: - Public methods

        public func body(_ task: Content) async throws -> Input {
            var attempt = 1
            var result = try await task.result()

            while attempt < maxAttempts,
                result.head.status.code == 401,
                let challengeHeader = result.head.headers.first(name: "WWW-Authenticate"),
                let challenge = DigestChallenge(headerValue: challengeHeader)
            {
                credential.challenge = challenge
                attempt += 1
                result = try await task.result()
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
    /// the same request -- this modifier only ever stores the challenge it saw; the property is
    /// what turns it into a header on the retry. See ``DigestCredential``'s own doc comment for
    /// the shared-state contract between the two.
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
    /// - Parameters:
    ///    - credential: The same instance given to the paired ``DigestAuthentication`` property.
    ///    - maxAttempts: How many times to send the request in total -- one initial, unauthenticated
    ///    probe plus up to `maxAttempts - 1` authenticated retries. Defaults to `2` (one probe, one
    ///    retry), which is all RFC 7616's challenge/response flow ever calls for; a higher value
    ///    only matters if the server is expected to rotate its nonce mid-flow.
    ///
    /// - Returns: The modified task, retrying once to answer a Digest challenge.
    ///
    public func digestAuthentication(
        _ credential: DigestCredential,
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
