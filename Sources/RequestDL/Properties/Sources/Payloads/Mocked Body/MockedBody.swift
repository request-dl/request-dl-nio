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

/// A representation of the HTTP body data in a ``RequestDL/MockedTask``'s mocked response.
///
/// `MockedBody` mirrors ``RequestDL/Payload``'s initializers — a dictionary, an encodable value, a
/// string, raw `Data`, or a file — but declaring one only ever contributes to the mocked response
/// (and its `Content-Type`/`Content-Length`), never to the outgoing request it stands in for.
/// ``RequestDL/Payload`` also works inside a ``RequestDL/MockedTask``'s content — the two share the
/// same underlying mechanism — but its name and documentation describe an outgoing request body,
/// which reads as backwards in this context. Prefer `MockedBody` there.
///
/// ```swift
/// MockedTask {
///     BaseURL("localhost")
///     MockedBody(
///         data: Data(
///             """
///             {
///                 "id": 1,
///                 "name": "John Doe",
///                 "email": "johndoe@example.com"
///             }
///             """.utf8
///         )
///     )
/// }
/// ```
public struct MockedBody: Property {

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
    /// Initializes a `MockedBody` with a JSON object.
    ///
    /// - Parameters:
    ///    - json: A JSON object to be serialized.
    ///    - options: Options for serializing the JSON object.
    ///    - contentType: The content type of the mocked body (default is JSON).
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
    /// Initializes a `MockedBody` with an encodable value.
    ///
    /// - Parameters:
    ///    - object: An encodable value to be serialized.
    ///    - encoder: An encoder to use for the serialization.
    ///    - contentType: The content type of the mocked body (default is JSON).
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
    /// Initializes a `MockedBody` with a string verbatim.
    ///
    /// - Parameters:
    ///    - verbatim: The verbatim string value.
    ///    - contentType: The content type of the mocked body (default is text).
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
    /// Initializes a `MockedBody` with raw data.
    ///
    /// - Parameters:
    ///    - data: The raw data.
    ///    - contentType: The content type of the mocked body (default is octet-stream).
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
    /// Initializes a `MockedBody` with a file URL.
    ///
    /// - Parameters:
    ///    - url: The file URL.
    ///    - contentType: The content type of the mocked body.
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

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<MockedBody>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return .leaf(
            MockedBodyNode(
                factory: property.factory,
                charset: inputs.environment.charset,
                urlEncoder: inputs.environment.urlEncoder,
                chunkSize: inputs.environment.payloadChunkSize
            )
        )
    }
}
