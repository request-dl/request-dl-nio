//
// See LICENSE for this package's licensing information.
//

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A `PayloadEncoder` stand-in for a third-party format (Protobuf, MessagePack, ...): it only
/// knows how to encode `String`, so any other value exercises the error path.
struct PayloadEncoderMock: PayloadEncoder {

    // MARK: - Internal properties

    let contentType: ContentType

    // MARK: - Inits

    init(contentType: ContentType = "application/x-mock") {
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func encode<T: Sendable>(_ value: T) throws -> Data {
        guard let string = value as? String else {
            throw EncodingPayloadError(.invalidStringEncoding)
        }

        return Data(string.utf8)
    }
}
