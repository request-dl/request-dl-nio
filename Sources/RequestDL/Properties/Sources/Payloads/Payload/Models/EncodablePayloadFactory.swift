/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct EncodablePayloadFactory: Sendable, PayloadFactory {

    // MARK: - Internal properties

    let encode: @Sendable (JSONEncoder) throws -> Data
    let contentType: ContentType?

    // MARK: - Private properties

    private let encoder: JSONEncoder

    // MARK: - Inits

    init<Object: Encodable>(
        _ object: Object,
        encoder: JSONEncoder,
        contentType: ContentType?
    ) {
        self.encode = { try $0.encode(object) }
        self.encoder = encoder
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> Internals.AnyBuffer {
        try Internals.DataBuffer(encode(encoder))
    }
}
