//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import RequestDLInternals
#endif

struct PayloadEncoderFactory: Sendable, PayloadFactory {

    // MARK: - Internal properties

    let encode: @Sendable (any PayloadEncoder) throws -> Data
    let explicitEncoder: (any PayloadEncoder)?
    let contentType: ContentType?

    // MARK: - Inits

    init<Value: Sendable>(
        _ value: Value,
        encoder: (any PayloadEncoder)?,
        contentType: ContentType?
    ) {
        self.encode = { try $0.encode(value) }
        self.explicitEncoder = encoder
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        // `encoder: nil` at the `Payload` call site defers to whatever `.payloadEncoder(_:)`
        // put in the environment. Neither present is a caller error, not a bug to work around.
        guard let encoder = explicitEncoder ?? input.payloadEncoder else {
            throw EncodingPayloadError(.missingPayloadEncoder)
        }

        // Unlike `EncodablePayloadFactory`, there is no form-urlencoded path here: a
        // `PayloadEncoder` produces an opaque, atomic blob (Protobuf, MessagePack, ...), not a
        // JSON object whose fields could be exploded into query items.
        let data = try encode(encoder)

        return await .init(
            contentType: contentType ?? encoder.contentType,
            source: .buffer(Internals.DataBuffer(data))
        )
    }
}
