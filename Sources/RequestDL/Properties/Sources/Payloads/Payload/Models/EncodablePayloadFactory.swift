/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
        let data = try encode(encoder)

        guard contentType.isFormURLEncoded else {
            return .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(data))
            )
        }

        switch try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
        case let array as [Any]:
            return try input.jsonObject(array, contentType: contentType)
        case let dictionary as [AnyHashable: Any]:
            return try input.jsonObject(dictionary, contentType: contentType)
        default:
            return .init(
                contentType: contentType,
                source: .buffer(Internals.DataBuffer(data))
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
