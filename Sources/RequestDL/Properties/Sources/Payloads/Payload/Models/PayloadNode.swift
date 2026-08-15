//
// See LICENSE for this package's licensing information.
//

struct PayloadNode: PropertyNode {

    // MARK: - Internal properties

    let factory: PayloadFactory
    let charset: Charset
    let urlEncoder: URLEncoder
    let chunkSize: Int?
    let payloadEncoder: (any PayloadEncoder)?

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
            setBodyWithBuffer(
                buffer: buffer,
                output: output,
                make: &make
            )

        case .urlEncoded(let queries):
            guard !sendsFieldsAsQuery(make.requestConfiguration.method) else {
                removeAnySetHeaders(&make.requestConfiguration.headers)
                make.requestConfiguration.queries.append(contentsOf: queries)
                return
            }

            let buffer = try await Internals.DataBuffer(
                input.charset.encode(queries.joined())
            )

            setBodyWithBuffer(
                buffer: buffer,
                output: output,
                make: &make
            )
        }
    }

    // MARK: - Private methods

    /// Whether the encoded fields belong in the URL rather than in a body.
    ///
    /// True with no method set, and for the two methods that carry no body.
    ///
    /// - Important: Must compare uppercased. HTTP methods are conventionally uppercase but the
    /// value comes from the caller — without normalizing, `.method("get")` falls through and
    /// sends the fields as a body instead of as a query.
    private func sendsFieldsAsQuery(_ method: String?) -> Bool {
        guard let method = method?.uppercased() else {
            return true
        }

        return method == "GET" || method == "HEAD"
    }

    private func setBodyWithBuffer(
        buffer: Internals.AnyBuffer,
        output: PayloadOutput,
        make: inout Make
    ) {
        make.requestConfiguration.headers.set(
            name: "Content-Type",
            value: String(output.contentType)
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
    }

    private func removeAnySetHeaders(_ headers: inout HTTPHeaders) {
        headers.remove(name: "Content-Type")
        headers.remove(name: "Content-Length")
    }
}
