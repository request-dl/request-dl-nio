/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A representation of the HTTP body data in a request.

 A `Payload` can be initialized with various types of data: a dictionary, an encodable value, a string, or a raw
 `Data`.

 The body data is used in HTTP requests with the purpose of carrying information. When making a HTTP request,
 the request body is used to send information to the server. The server reads the information and acts upon it, for
 example, by returning a specific response or by modifying its behavior.

 To create a `Payload`, initialize an instance with a dictionary, an encodable value, a string, or a raw `Data.

 Example:

 ```swift
 let bodyDict = ["name": "John", "age": 28]

 DataTask {
     BaseURL("apple.com")
     RequestMethod(.post)
     Payload(bodyDict)
 }
 ```

 ## Topics

 ### Sending raw bytes

 - ``RequestDL/Payload/init(data:contentType:)``

 ### Sending verbatim texts

 - ``RequestDL/Payload/init(verbatim:contentType:)``

 ### Sending files

 - ``RequestDL/Payload/init(url:contentType:)``

 ### Sending Encodable

 - ``RequestDL/Payload/init(_:encoder:contentType:)``

 ### Sending JSON objects

 - ``RequestDL/Payload/init(_:options:contentType:)``
 */
public struct Payload: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let factory: PayloadFactory

    // MARK: - Inits

    /**
     Initializes a `Payload` with a JSON object.

     - Parameters:
        - json: A JSON object to be serialized.
        - options: Options for serializing the JSON object.
        - contentType: The content type of the payload (default is JSON).
     */
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

    /**
     Initializes a `Payload` with an encodable value.

     - Parameters:
        - object: An encodable value to be serialized.
        - encoder: An encoder to use for the serialization.
        - contentType: The content type of the payload (default is JSON).
     */
    public init<Object: Encodable>(
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

    /**
     Initializes a `Payload` with a string verbatim.

     - Parameters:
        - verbatim: The verbatim string value.
        - contentType: The content type of the payload (default is text).
     */
    public init<Verbatim: StringProtocol>(
        verbatim: Verbatim,
        contentType: ContentType = .text
    ) {
        factory = StringPayloadFactory(
            verbatim: verbatim,
            contentType: contentType
        )
    }

    /**
     Initializes a `Payload` with raw data.

     - Parameters:
        - data: The raw data.
        - contentType: The content type of the payload (default is octet-stream).
     */
    public init(
        data: Data,
        contentType: ContentType = .octetStream
    ) {
        factory = DataPayloadFactory(
            data: data,
            contentType: contentType
        )
    }

    /**
     Initializes a `Payload` with a file URL.

     - Parameters:
        - url: The file URL.
        - contentType: The content type of the payload.
     */
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
        property: _GraphValue<Payload>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return .leaf(PayloadNode(
            factory: property.factory,
            charset: inputs.environment.charset,
            urlEncoder: inputs.environment.urlEncoder,
            chunkSize: inputs.environment.payloadChunkSize
        ))
    }
}
