/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
        let output = try factory(.init(
            method: nil,
            charset: charset,
            urlEncoder: urlEncoder
        ))

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

        if let additionalHeaders {
            headers = headers.merging(additionalHeaders, by: +)
        }

        headers.set(name: "Content-Length", value: String(buffer.estimatedBytes))

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
