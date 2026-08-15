//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct PayloadEncoderFactory: Sendable, PayloadFactory {

    // MARK: - Internal properties

    let encode: @Sendable () throws -> Data
    let contentType: ContentType

    // MARK: - Inits

    init<Value: Sendable, Encoder: PayloadEncoder>(
        _ value: Value,
        encoder: Encoder,
        contentType: ContentType?
    ) {
        self.encode = { try encoder.encode(value) }
        self.contentType = contentType ?? encoder.contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        // Unlike `EncodablePayloadFactory`, there is no form-urlencoded path here: a
        // `PayloadEncoder` produces an opaque, atomic blob (Protobuf, MessagePack, ...), not a
        // JSON object whose fields could be exploded into query items.
        let data = try encode()

        return await .init(
            contentType: contentType,
            source: .buffer(Internals.DataBuffer(data))
        )
    }
}
