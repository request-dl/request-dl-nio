//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
#endif

struct EncodablePayloadFactory: Sendable, PayloadFactory {

    // MARK: - Internal properties

    let encode: @Sendable (JSONEncoder) throws -> Data
    let contentType: ContentType

    // MARK: - Private properties

    private let encoder: JSONEncoder

    // MARK: - Inits

    init<Object: Encodable & Sendable>(
        _ object: Object,
        encoder: JSONEncoder,
        contentType: ContentType
    ) {
        self.encode = { try $0.encode(object) }
        self.encoder = encoder
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        // Encoded once, with the encoder the caller configured, and reused on every path.
        //
        // The form-urlencoded path used to re-encode through a default `JSONEncoder`, which
        // silently dropped the caller's settings. That matters more here than anywhere else:
        // on this path the JSON keys become the form field names, so a caller who asked for
        // `.convertToSnakeCase` was quietly sending camel case over the wire. The fallback
        // branch then encoded a third time, with the right encoder, producing a body that did
        // not match the object just inspected.
        let data = try encode(encoder)

        guard contentType.isFormURLEncoded else {
            return await .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(data))
            )
        }

        // Parsed through `JSONDecoder` rather than `JSONSerialization`, which is not part of
        // `FoundationEssentials`. `JSONPayloadFactory` is gated behind `canImport(Darwin)` for
        // exactly that reason, and this file was reaching for the same type with no guard at
        // all, so the form-urlencoded path could not build off Apple.
        switch Internals.JSONValue.decoding(data) {
        case .object(let object):
            return try input.jsonObject(
                object.mapValues(\.rawValue) as [AnyHashable: Any],
                contentType: contentType
            )

        case .array(let array):
            return try input.jsonObject(
                array.map(\.rawValue),
                contentType: contentType
            )

        default:
            // A top level fragment, or something that did not parse. Sent as encoded, which is
            // what the `default` branch of the previous version did.
            return await .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(data))
            )
        }
    }
}
