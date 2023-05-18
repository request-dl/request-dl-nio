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
        self.name = name
        self.filename = filename
        self.contentType = factory.contentType ?? .octetStream
        self.additionalHeaders = additionalHeaders
        self.buffer = try factory()
    }

    // MARK: - Internal methods

    func headers() -> HTTPHeaders {
        var headers = HTTPHeaders()

        headers.set(name: "Content-Disposition", value: contentDisposition())
        headers.set(name: "Content-Type", value: String(contentType))

        if var additionalHeaders {
            additionalHeaders.setContentLengthIfNeeded(buffer.estimatedBytes)
            return headers.merging(additionalHeaders, by: +)
        } else {
            headers.setContentLengthIfNeeded(buffer.estimatedBytes)
            return headers
        }
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
