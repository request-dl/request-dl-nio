/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct JSONPayloadFactory: @unchecked Sendable, PayloadFactory {

    // MARK: - Internal properties

    let jsonObject: Any
    let options: JSONSerialization.WritingOptions
    let contentType: ContentType?

    // MARK: - Private properties

    // MARK: - Inits

    init(
        jsonObject: Any,
        options: JSONSerialization.WritingOptions,
        contentType: ContentType?
    ) {
        self.jsonObject = jsonObject
        self.options = options
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> Internals.AnyBuffer {
        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: options
        )

        return Internals.DataBuffer(data)
    }
}
