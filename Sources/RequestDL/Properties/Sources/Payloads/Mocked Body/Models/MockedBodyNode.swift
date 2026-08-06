//
// See LICENSE for this package's licensing information.
//

struct MockedBodyNode: PropertyNode {

    // MARK: - Internal properties

    let factory: PayloadFactory
    let charset: Charset
    let urlEncoder: URLEncoder
    let chunkSize: Int?

    // MARK: - Internal methods

    /// Runs the factory and installs the result as the mocked response body.
    ///
    /// - Important: Unlike `PayloadNode`, this never rewrites the result into query items for a
    /// GET/HEAD method — there is no "outgoing request" a mocked response's fields could belong
    /// to instead, so a form-urlencoded ``MockedBody`` always becomes the response body.
    func make(_ make: inout Make) async throws {
        let input = PayloadInput(
            method: make.requestConfiguration.method,
            charset: charset,
            urlEncoder: urlEncoder
        )

        let output = try await factory(input)
        let buffer: Internals.AnyBuffer

        switch output.source {
        case .buffer(let outputBuffer):
            buffer = outputBuffer

        case .urlEncoded(let queries):
            buffer = try await Internals.DataBuffer(
                charset.encode(queries.joined())
            )
        }

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
}
