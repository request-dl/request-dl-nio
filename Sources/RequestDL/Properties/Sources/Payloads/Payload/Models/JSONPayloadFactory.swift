//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// `@unchecked` because `jsonObject` is `Any`, which cannot be `Sendable`. The assumption is
// that a JSON object is made of value types, which holds for anything `JSONSerialization`
// accepts, but nothing here enforces it: a mutable reference smuggled in would cross isolation
// boundaries unchecked.
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
