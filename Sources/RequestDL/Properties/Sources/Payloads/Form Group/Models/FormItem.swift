/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormItem: Sendable {

    // MARK: - Internal methods

    let buffer: Internals.AnyBuffer

    // MARK: - Private properties

    private let name: String
    private let filename: String?
    private let contentType: ContentType
    private let additionalHeaders: HTTPHeaders?

    // MARK: - Inits

    init(
        name: String,
        filename: String? = nil,
        additionalHeaders: HTTPHeaders? = nil,
        factory: PayloadFactory
    ) throws {
        let output = try factory(.empty)

        guard case .buffer(let buffer) = output.source else {
            fatalError()
        }

        self.name = name
        self.filename = filename
        self.contentType = output.contentType
        self.additionalHeaders = additionalHeaders
        self.buffer = buffer
    }

    // MARK: - Internal methods

    func headers() -> HTTPHeaders {
        var headers = HTTPHeaders()

        headers.set(name: "Content-Disposition", value: contentDisposition())
        headers.set(name: "Content-Type", value: String(contentType))

        if let additionalHeaders {
            headers = headers.merging(additionalHeaders, by: +)
        }

        headers.set(name: "Content-Length", value: String(buffer.estimatedBytes))

        return headers
    }

    // MARK: - Private methods

    private func contentDisposition() -> String {
        var contentDisposition = "form-data; name=\"\(name)\""

        if let filename {
            contentDisposition += "; filename=\"\(filename)\""
        }

        return contentDisposition
    }
}
