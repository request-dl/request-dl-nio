//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
import class Foundation.JSONEncoder
#if canImport(Darwin)
import class Foundation.JSONSerialization
#endif
#endif

/// A representation of the HTTP body data in a request.
///
/// A `Payload` can be initialized with various types of data: a dictionary, an encodable value, a string, or a raw
/// `Data`.
///
/// The body data is used in HTTP requests with the purpose of carrying information. When making a HTTP request,
/// the request body is used to send information to the server. The server reads the information and acts upon it, for
/// example, by returning a specific response or by modifying its behavior.
///
/// To create a `Payload`, initialize an instance with a dictionary, an encodable value, a string, or a raw `Data.
///
/// ```swift
/// let bodyDict = ["name": "John", "age": 28]
///
/// DataTask {
///     BaseURL("apple.com")
///     RequestMethod(.post)
///     Payload(bodyDict)
/// }
/// ```
///
/// ## Topics
///
/// ### Sending raw bytes
///
/// - ``RequestDL/Payload/init(data:contentType:)``
///
/// ### Sending verbatim texts
///
/// - ``RequestDL/Payload/init(verbatim:contentType:)``
///
/// ### Sending files
///
/// - ``RequestDL/Payload/init(url:contentType:)``
/// - ``RequestDL/Payload/init(url:from:contentType:)``
///
/// ### Sending Encodable
///
/// - ``RequestDL/Payload/init(_:encoder:contentType:)-(Object,_,_)``
///
/// ### Sending values through a custom encoder
///
/// - ``RequestDL/PayloadEncoder``
///
/// ### Sending JSON objects
///
/// - ``RequestDL/Payload/init(_:options:contentType:)``
public struct Payload: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let factory: PayloadFactory

    // MARK: - Inits

    #if canImport(Darwin)
    ///
    /// Initializes a `Payload` with a JSON object.
    ///
    /// - Parameters:
    ///    - json: A JSON object to be serialized.
    ///    - options: Options for serializing the JSON object.
    ///    - contentType: The content type of the payload (default is JSON).
    ///
    public init(
        _ json: Any,
        options: JSONSerialization.WritingOptions = .prettyPrinted,
        contentType: ContentType = .json
    ) {
        factory = JSONPayloadFactory(
            jsonObject: json,
            options: options,
            contentType: contentType
        )
    }
    #endif

    ///
    /// Initializes a `Payload` with an encodable value.
    ///
    /// - Parameters:
    ///    - object: An encodable value to be serialized.
    ///    - encoder: An encoder to use for the serialization.
    ///    - contentType: The content type of the payload (default is JSON).
    ///
    public init<Object: Encodable & Sendable>(
        _ object: Object,
        encoder: JSONEncoder = .init(),
        contentType: ContentType = .json
    ) {
        factory = EncodablePayloadFactory(
            object,
            encoder: encoder,
            contentType: contentType
        )
    }

    ///
    /// Initializes a `Payload` with a value serialized through a custom ``PayloadEncoder``.
    ///
    /// Pass `encoder: nil` to defer to the default set via ``Property/payloadEncoder(_:)`` on an
    /// enclosing property. Resolving to no encoder at all — neither passed here nor set on the
    /// environment — throws ``EncodingPayloadError`` with context `.missingPayloadEncoder`.
    ///
    /// - Parameters:
    ///    - value: The value to be serialized.
    ///    - encoder: The encoder used to serialize `value`, or `nil` to use the environment's.
    ///    - contentType: The content type of the payload. Defaults to the encoder's own
    ///      ``PayloadEncoder/contentType``.
    ///
    public init<Value: Sendable>(
        _ value: Value,
        encoder: (any PayloadEncoder)?,
        contentType: ContentType? = nil
    ) {
        factory = PayloadEncoderFactory(
            value,
            encoder: encoder,
            contentType: contentType
        )
    }

    ///
    /// Initializes a `Payload` with a string verbatim.
    ///
    /// - Parameters:
    ///    - verbatim: The verbatim string value.
    ///    - contentType: The content type of the payload (default is text).
    ///
    public init<Verbatim: StringProtocol>(
        verbatim: Verbatim,
        contentType: ContentType = .text
    ) {
        factory = StringPayloadFactory(
            verbatim: verbatim,
            contentType: contentType
        )
    }

    ///
    /// Initializes a `Payload` with raw data.
    ///
    /// - Parameters:
    ///    - data: The raw data.
    ///    - contentType: The content type of the payload (default is octet-stream).
    ///
    public init(
        data: Data,
        contentType: ContentType = .octetStream
    ) {
        factory = DataPayloadFactory(
            data: data,
            contentType: contentType
        )
    }

    ///
    /// Initializes a `Payload` with a file URL.
    ///
    /// - Parameters:
    ///    - url: The file URL.
    ///    - contentType: The content type of the payload.
    ///
    public init(
        url: URL,
        contentType: ContentType
    ) {
        factory = FilePayloadFactory(
            url: url,
            contentType: contentType
        )
    }

    ///
    /// Initializes a `Payload` with a file URL, starting the upload's byte stream at an
    /// arbitrary offset instead of from the beginning of the file.
    ///
    /// This does not implement resumable upload by itself — HTTP has no universal mechanism for
    /// that. It provides the one transport-agnostic building block a resume implementation needs:
    /// a way to start streaming from a byte position other than zero. Track how many bytes were
    /// sent (e.g. via ``UploadStep``), and on failure, start a fresh upload with a payload
    /// beginning at that offset.
    ///
    /// - Parameters:
    ///    - url: The file URL.
    ///    - offset: The byte offset at which the upload's stream should start.
    ///    - contentType: The content type of the payload.
    ///
    /// - Note: `offset` is only validated once the request is resolved, not at initialization
    /// time. Resolving a request with a `Payload` whose offset is greater than the file's
    /// current size throws ``InvalidPayloadOffsetError``.
    ///
    public init(
        url: URL,
        from offset: UInt64,
        contentType: ContentType
    ) {
        factory = FilePayloadFactory(
            url: url,
            contentType: contentType,
            offset: offset
        )
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Payload>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return .leaf(
            PayloadNode(
                factory: property.factory,
                charset: inputs.environment.charset,
                urlEncoder: inputs.environment.urlEncoder,
                chunkSize: inputs.environment.payloadChunkSize,
                payloadEncoder: inputs.environment.payloadEncoder
            )
        )
    }
}
