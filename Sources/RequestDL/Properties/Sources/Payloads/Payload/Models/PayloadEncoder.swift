//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A pluggable serialization format for ``Payload``.
///
/// `PayloadEncoder` lets a value be turned into the bytes of a request body using a format other
/// than JSON — Protobuf, MessagePack, or any other serializer a consumer wants to plug in — the
/// same way `Payload(_:encoder:contentType:)` already does for `Encodable` + `JSONEncoder`.
///
/// ```swift
/// struct ProtobufEncodingError: Error {}
///
/// struct ProtobufPayloadEncoder: PayloadEncoder {
///     var contentType: ContentType = "application/x-protobuf"
///
///     func encode<T: Sendable>(_ value: T) throws -> Data {
///         guard let message = value as? SwiftProtobuf.Message else {
///             throw ProtobufEncodingError()
///         }
///         return try message.serializedData()
///     }
/// }
///
/// DataTask {
///     BaseURL("apple.com")
///     RequestMethod(.post)
///     Payload(myProtoMessage, encoder: ProtobufPayloadEncoder())
/// }
/// ```
///
/// - Important: `encode(_:)` turns a value into a single, complete `Data` blob. A serializer
/// operates on a typed value, not on an arbitrary file — sending an existing file verbatim is
/// already covered by ``Payload/init(url:contentType:)``.
public protocol PayloadEncoder: Sendable {

    /// The content type declared for the encoded body, unless the caller overrides it.
    var contentType: ContentType { get }

    /// Encodes `value` into the raw bytes of the request body.
    func encode<T: Sendable>(_ value: T) throws -> Data
}
