/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct JSONPayloadFactory: @unchecked Sendable, PayloadFactory {

    // MARK: - Internal properties

    let jsonObject: Any
    let options: JSONSerialization.WritingOptions
    let contentType: ContentType

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
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw EncodingPayloadError(.invalidJSONObject)
        }

        return try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: options
        )
    }
}
