//
// See LICENSE for this package's licensing information.
//

struct FormItem: Sendable {

    struct Output {
        let headers: HTTPHeaders
        let buffer: Internals.AnyBuffer
    }

    // MARK: - Private properties

    private let name: String
    private let filename: String?
    private let additionalHeaders: HTTPHeaders?
    private let charset: Charset
    private let urlEncoder: URLEncoder
    private let factory: PayloadFactory

    // MARK: - Inits

    init(
        name: String,
        filename: String?,
        additionalHeaders: HTTPHeaders?,
        charset: Charset,
        urlEncoder: URLEncoder,
        factory: PayloadFactory
    ) {
        self.name = name
        self.filename = filename
        self.additionalHeaders = additionalHeaders
        self.charset = charset
        self.urlEncoder = urlEncoder
        self.factory = factory
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> Output {
        let output = try factory(
            .init(
                method: nil,
                charset: charset,
                urlEncoder: urlEncoder
            )
        )

        switch output.source {
        case .buffer(let buffer):
            return .init(
                headers: makeHeader(buffer, for: output.contentType),
                buffer: buffer
            )
        case .urlEncoded(let queries):
            let queries = queries.map { $0.build() }.joined()
            let data = try charset.encode(queries)
            let buffer = Internals.DataBuffer(data)
            return .init(
                headers: makeHeader(buffer, for: output.contentType),
                buffer: buffer
            )
        }
    }

    // MARK: - Private methods

    private func makeHeader(
        _ buffer: Internals.AnyBuffer,
        for contentType: ContentType
    ) -> HTTPHeaders {
        var headers = HTTPHeaders()

        headers.set(name: "Content-Disposition", value: contentDisposition())
        headers.set(name: "Content-Type", value: String(contentType))
        // `readableBytes`, not `estimatedBytes`. The estimate is the size of the whole backing
        // store, while what goes on the wire is what the cursor can still read, so a partially
        // read buffer declared a part longer than it sends. It is also arithmetic rather than a
        // stat call, which for a file backed part used to happen once per part.
        headers.set(name: "Content-Length", value: String(buffer.readableBytes))

        if let additionalHeaders {
            headers = headers.merging(additionalHeaders) { lhs, _ in lhs }
        }

        return headers
    }

    private func contentDisposition() -> String {
        var contentDisposition = "form-data; name=\"\(name)\""

        if let filename {
            contentDisposition += "; filename=\"\(filename)\""
        }

        return contentDisposition
    }
}
