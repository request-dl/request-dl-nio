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
 */
public struct Payload: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: PayloadNode.Source

    // MARK: - Inits

    /**
     Initializes a `Payload` with a dictionary.

     - Parameters:
        - dictionary: A dictionary to be serialized.
        - options: Options for serializing the dictionary.
     */
    public init(
        _ json: Any,
        options: JSONSerialization.WritingOptions = .prettyPrinted,
        contentType: ContentType? = nil
    ) {
        source = .json(JSONPayloadFactory(
            jsonObject: json,
            options: options,
            contentType: contentType
        ))
    }

    /**
     Initializes a `Payload` with an encodable value.

     - Parameters:
        - value: An encodable value to be serialized.
        - encoder: An encoder to use for the serialization.
     */
    public init<Object: Encodable>(
        _ object: Object,
        encoder: JSONEncoder = .init(),
        contentType: ContentType? = nil
    ) {
        source = .encoded(EncodablePayloadFactory(
            object,
            encoder: encoder,
            contentType: contentType
        ))
    }

    public init<Verbatim: StringProtocol, Encoding: StringEncoding>(
        verbatim: Verbatim,
        using encoding: Encoding,
        contentType: ContentType = .text
    ) {
        source = .string(StringPayloadFactory(
            verbatim: verbatim,
            encoding: encoding,
            contentType: contentType
        ))
    }

    public init(
        data: Data,
        contentType: ContentType? = nil
    ) {
        source = .data(DataPayloadFactory(
            data: data,
            contentType: contentType
        ))
    }

    public init(
        url: URL,
        contentType: ContentType? = nil
    ) {
        source = .url(FilePayloadFactory(
            url: url,
            contentType: contentType
        ))
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Payload>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return .leaf(PayloadNode(
            source: property.source,
            urlEncoder: inputs.environment.urlEncoder,
            partLength: inputs.environment.payloadPartLength
        ))
    }
}

// MARK: - Deprecated

extension Payload {


    /**
     Initializes a `Payload` with a string.

     - Parameters:
        - string: A string to be used as the body data.
        - encoding: The encoding to use when converting the string to data.
     */
    @available(*, deprecated, renamed: "init(verbatim:using:)")
    public init(
        _ string: String,
        using encoding: String.Encoding = .utf8
    ) {
        self.init(
            verbatim: string,
            using: _StringEncoding(encoding)
        )
    }

    /**
     Initializes a `Payload` with raw `Data`.

     - Parameters:
        - data: The raw data to be used as the body.
     */
    @available(*, deprecated, renamed: "init(data:)")
    public init(_ data: Data) {
        self.init(data: data)
    }

    /**
     Initializes a `Payload` with file `URL`.

     - Parameters:
        - fileURL: The file url to be used as the body.
     */
    @available(*, deprecated, renamed: "init(url:)")
    public init(_ fileURL: URL) {
        self.init(url: fileURL)
    }
}
