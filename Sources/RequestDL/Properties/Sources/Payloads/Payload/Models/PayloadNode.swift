//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct PayloadNode: PropertyNode {

    // MARK: - Internal properties

    let factory: PayloadFactory
    let charset: Charset
    let urlEncoder: URLEncoder
    let chunkSize: Int?
    let payloadEncoder: (any PayloadEncoder)?

    /// Captured from `inputs.environment` at `_makeProperty` time; see `RequestConfiguration
    /// .compression`'s own doc comment for why this can't be read from inside `make(_:)` itself.
    let compression: (any Compressor)?
    let compressionDuplicateHeaderBehavior: CompressionDuplicateHeaderBehavior
    let shouldCompressBodyData: (@Sendable (Int) -> Bool)?

    // MARK: - Internal methods

    /// Runs the factory and installs the result, either as a query string or as a body.
    func make(_ make: inout Make) async throws {
        let input = PayloadInput(
            method: make.requestConfiguration.method,
            charset: charset,
            urlEncoder: urlEncoder,
            payloadEncoder: payloadEncoder
        )

        let output = try await factory(input)

        switch output.source {
        case .buffer(let buffer):
            Self.setBodyWithBuffer(
                buffer: buffer,
                contentType: output.contentType,
                chunkSize: chunkSize,
                compression: compression,
                compressionDuplicateHeaderBehavior: compressionDuplicateHeaderBehavior,
                shouldCompressBodyData: shouldCompressBodyData,
                make: &make
            )

        case .urlEncoded(let queries):
            // Deliberately *not* decided here, against `make.requestConfiguration.method` as it
            // stands at this point in the walk: nodes run in declaration order, so a `Payload`
            // declared before a `RequestMethod(.post)` in the same property tree would still see
            // `method == nil` -- indistinguishable from "no method at all", which
            // `sendsFieldsAsQuery(_:)` treats as query-string -- even though the method is about
            // to become `POST`. `PendingURLEncodedPayload` stashes everything needed to finish
            // this decision, and `Resolve` applies it once every node (including whichever
            // `RequestMethod` wins) has run. See `PendingURLEncodedPayload`'s own doc comment.
            make.pendingURLEncodedPayloads.append(
                PendingURLEncodedPayload(
                    queries: queries,
                    contentType: output.contentType,
                    charset: charset,
                    chunkSize: chunkSize,
                    compression: compression,
                    compressionDuplicateHeaderBehavior: compressionDuplicateHeaderBehavior,
                    shouldCompressBodyData: shouldCompressBodyData
                )
            )
        }
    }

    // MARK: - Internal static methods

    /// Shared with `PendingURLEncodedPayload.resolve(into:)`, which reaches this same body-side
    /// once it has decided (after the whole tree resolves) that its fields belong in the body
    /// rather than the query string.
    static func setBodyWithBuffer(
        buffer: Internals.AnyBuffer,
        contentType: ContentType,
        chunkSize: Int?,
        compression: (any Compressor)?,
        compressionDuplicateHeaderBehavior: CompressionDuplicateHeaderBehavior,
        shouldCompressBodyData: (@Sendable (Int) -> Bool)?,
        make: inout Make
    ) {
        // Only fills in a default, never overrides an explicit `RequestMethod`: whichever
        // node runs first wins, since `RequestMethod`'s own node assigns unconditionally.
        //
        // A body attached to whatever method ends up unset otherwise falls through to `"GET"` at
        // request-build time, which AsyncHTTPClient tolerates silently but URLSession/CFNetwork
        // does not: a GET carrying a body fails outright (`NSURLErrorDataLengthExceedsMaximum`,
        // confirmed against a real server, not LocalServer- or beta-OS-specific).
        if make.requestConfiguration.method == nil {
            make.requestConfiguration.method = "POST"
        }

        make.requestConfiguration.headers.set(
            name: "Content-Type",
            value: String(contentType)
        )

        let body = RequestBody(
            chunkSize: chunkSize,
            buffers: [buffer]
        )

        if body.totalSize > .zero {
            make.requestConfiguration.headers.set(
                name: "Content-Length",
                value: String(body.totalSize)
            )
        } else {
            make.requestConfiguration.headers.remove(name: "Content-Length")
        }

        make.requestConfiguration.body = body

        if let compression {
            make.requestConfiguration.compression = InternalsCompressionAlgorithmAdapter(algorithm: compression)
            make.requestConfiguration.compressionDuplicateHeaderBehavior = compressionDuplicateHeaderBehavior.build()
            make.requestConfiguration.shouldCompressBodyData = shouldCompressBodyData
        }
    }

    /// Whether the encoded fields belong in the URL rather than in a body.
    ///
    /// True with no method set, and for the two methods that carry no body.
    ///
    /// - Important: Must compare uppercased. HTTP methods are conventionally uppercase but the
    /// value comes from the caller — without normalizing, `.method("get")` falls through and
    /// sends the fields as a body instead of as a query.
    static func sendsFieldsAsQuery(_ method: String?) -> Bool {
        guard let method = method?.uppercased() else {
            return true
        }

        return method == "GET" || method == "HEAD"
    }
}
