//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
import class Foundation.JSONSerialization
#else
import Foundation
#endif

#if canImport(Darwin)
/// Serialises a loosely typed JSON object.
///
/// - Important: Darwin only, and it has to be. This is the one factory that takes `Any` in, so
/// it cannot avoid `JSONSerialization`, which is not part of `FoundationEssentials`. Callers
/// that need a JSON body off Apple use the `Encodable` initialisers instead, which route
/// through ``EncodablePayloadFactory`` and only need `JSONEncoder`.
///
/// - Note: `@unchecked Sendable` because `jsonObject` is `Any`, which cannot be `Sendable`. The
/// assumption is that a JSON object is made of value types, which holds for anything
/// `JSONSerialization` accepts, but nothing here enforces it: a mutable reference smuggled in
/// would cross isolation boundaries unchecked.
struct JSONPayloadFactory: @unchecked Sendable, PayloadFactory {

    // MARK: - Internal properties

    let jsonObject: Any
    let options: JSONSerialization.WritingOptions
    let contentType: ContentType

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        guard contentType.isFormURLEncoded else {
            return try await .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(jsonToData()))
            )
        }

        switch jsonObject {
        case let array as [Any]:
            return try input.jsonObject(array, contentType: contentType)
        case let dictionary as [AnyHashable: Any]:
            return try input.jsonObject(dictionary, contentType: contentType)
        default:
            return try await .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(jsonToData()))
            )
        }
    }

    // MARK: - Private methods

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
#endif
