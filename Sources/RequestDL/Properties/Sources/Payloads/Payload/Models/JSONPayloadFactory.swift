/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct JSONPayloadFactory: @unchecked Sendable, PayloadFactory {

    // MARK: - Internal properties

    let jsonObject: Any
    let options: JSONSerialization.WritingOptions
    let contentType: ContentType

    // MARK: - Private properties

    // MARK: - Inits

    init(
        jsonObject: Any,
        options: JSONSerialization.WritingOptions,
        contentType: ContentType
    ) {
        self.jsonObject = jsonObject
        self.options = options
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput {
        guard contentType.isFormURLEncoded else {
            return .init(
                contentType: contentType,
                source: try .buffer(Internals.DataBuffer(jsonToData()))
            )
        }

        switch jsonObject {
        case let array as [Any]:
            return try input.jsonObject(array, contentType: contentType)
        case let dictionary as [AnyHashable: Any]:
            return try input.jsonObject(dictionary, contentType: contentType)
        default:
            return .init(
                contentType: contentType,
                source: try .buffer(Internals.DataBuffer(jsonToData()))
            )
        }
    }

    private func jsonToData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: options
        )
    }
}
