/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

struct EncodablePayloadFactory: Sendable, PayloadFactory {

    // MARK: - Internal properties

    let encode: @Sendable (JSONEncoder) throws -> Data
    let contentType: ContentType

    // MARK: - Private properties

    private let encoder: JSONEncoder

    // MARK: - Inits

    init<Object: Encodable>(
        _ object: Object,
        encoder: JSONEncoder,
        contentType: ContentType
    ) {
        self.encode = { try $0.encode(object) }
        self.encoder = encoder
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput {
        guard contentType.isFormURLEncoded else {
            return try .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(encode(encoder)))
            )
        }

        let jsonData = try encode(.init())

        switch try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed) {
        case let array as [Any]:
            return try input.jsonObject(array, contentType: contentType)
        case let dictionary as [AnyHashable: Any]:
            return try input.jsonObject(dictionary, contentType: contentType)
        default:
            return try .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(encode(encoder)))
            )
        }
    }

    func callAsFunction() throws -> Internals.AnyBuffer {
        try Internals.DataBuffer(encode(encoder))
    }
}

extension ContentType {

    var isFormURLEncoded: Bool {
        description.range(
            of: ContentType.formURLEncoded.description,
            options: .caseInsensitive
        ) != nil
    }
}
