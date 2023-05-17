/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct MultipartItem: Sendable {

    // MARK: - Internal methods

    let data: Internals.AnyBuffer

    // MARK: - Private properties

    private let name: String
    private let filename: String?
    private let contentType: ContentType?
    private let additionalHeaders: Internals.Headers?

    // MARK: - Inits

    init(
        name: String,
        filename: String? = nil,
        contentType: ContentType? = nil,
        additionalHeaders: Internals.Headers? = nil,
        data: Internals.AnyBuffer
    ) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.additionalHeaders = additionalHeaders
        self.data = data
    }

    // MARK: - Internal methods

    func headers() -> Internals.Headers {
        var headers = Internals.Headers()

        headers.set(name: "Content-Disposition", value: contentDisposition())

        if let contentType {
            headers.set(name: "Content-Type", value: String(contentType))
        }

        if let additionalHeaders {
            return headers.merging(additionalHeaders, by: +)
        } else {
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
