//
// See LICENSE for this package's licensing information.
//

private struct CacheCompletenessProbeProperty: Property {

    private struct Node: PropertyNode {

        let isEnabled: Bool

        func make(_ make: inout Make) async throws {
            make.requestConfiguration.probesCacheCompleteness = isEnabled
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let isEnabled: Bool

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<CacheCompletenessProbeProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(isEnabled: property.isEnabled))
    }
}

// MARK: - Property extension

extension Property {

    ///
    /// Lets a `.urlSession` response that has no `Content-Length` be cached after the server has
    /// confirmed, with one extra request, that the body arrived whole.
    ///
    /// By default such a response is not cached. CFNetwork reports a chunked response whose
    /// connection was closed exactly between two chunks as a successful, complete one, so on
    /// `.urlSession` a body with no `Content-Length` has nothing that proves it is not truncated,
    /// and a truncated body would be stored and served until it expires. The request still succeeds
    /// and the caller receives the response; the next request for the same URL goes to the network.
    /// The `.nio` executors end a chunked body with a terminator, so they do not need this: their
    /// chunked responses are cached as usual, and `.requiredExecutor(.nio)` is the way to get that
    /// on Apple platforms.
    ///
    /// With the probe on, once the body has been received and before it is stored, RequestDL sends
    /// the same `GET` again, asking for the one byte that would follow what was received
    /// (`Range: bytes=<n>-<n>`, with `If-Range` when the response had a strong `ETag` or a
    /// `Last-Modified`):
    ///
    /// - `416 Range Not Satisfiable` with `Content-Range: bytes */<n>`: nothing follows, the body is
    ///   whole, and the response is cached.
    /// - `206 Partial Content`: there is more, the body was cut, and the response is not cached.
    /// - Anything else (`200` from a server that does not do ranges, a `416` for another length, a
    ///   failure, no answer within 30 seconds): the probe does not decide, and the response is not
    ///   cached.
    ///
    /// ## Cost and limits
    ///
    /// - One extra request for every response that is written, `.urlSession` responses without a
    ///   `Content-Length` only. The caller does not wait for it: the response has already been
    ///   delivered. It goes out through the same session as the request.
    /// - It only runs for a response that sent `Accept-Ranges: bytes`, so a server that ignores
    ///   `Range` is never asked to send the body a second time.
    /// - It cannot decide for a response with a `Content-Encoding` (what `.urlSession` hands over is
    ///   the decoded body, and a range counts the encoded one), nor for a server that does not support
    ///   ranges on a chunked body, which is common for responses generated on the fly.
    /// - It confirms the length the server reports, not the bytes.
    /// - Without a strong validator, a resource that changed between the two requests can look whole.
    ///
    /// - Parameter isEnabled: Whether the probe is run. Defaults to `true`; it is off unless this
    ///   property is used.
    /// - Returns: A property that sets whether the completeness probe is run.
    ///
    @PropertyBuilder
    public func cacheCompletenessProbe(_ isEnabled: Bool = true) -> some Property {
        self
        CacheCompletenessProbeProperty(isEnabled: isEnabled)
    }
}
