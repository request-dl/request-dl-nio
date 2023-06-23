/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// swiftlint:disable file_length
/**
 A structure representing a form with headers.

 A `Form` object is used to encapsulate form data for HTTP requests. It allows you to specify the name,
 filename, content type, and data or URL associated with a form field. It also supports adding custom headers
 to the form.

 ```swift
 Form(
    name: "example",
    filename: "example.txt",
    contentType: .octetStream,
    data: someData
 )
 ```

 > Note: The `Headers` generic parameter represents the type of custom headers associated with the
 form. If no custom headers are needed, the default would be `EmptyProperty`.

 ## Topics

 ### Sending raw bytes

 - ``RequestDL/Form/init(name:filename:contentType:data:)``
 - ``RequestDL/Form/init(name:filename:contentType:data:headers:)``

 ### Sending verbatim texts

 - ``RequestDL/Form/init(name:filename:contentType:verbatim:)``
 - ``RequestDL/Form/init(name:filename:contentType:verbatim:headers:)``

 ### Sending files

 - ``RequestDL/Form/init(name:filename:contentType:url:)``
 - ``RequestDL/Form/init(name:filename:contentType:url:headers:)``

 ### Sending Encodable

 - ``RequestDL/Form/init(name:filename:contentType:value:encoder:)``
 - ``RequestDL/Form/init(name:filename:contentType:value:encoder:headers:)``

 ### Sending JSON objects

 - ``RequestDL/Form/init(name:filename:contentType:jsonObject:options:)``
 - ``RequestDL/Form/init(name:filename:contentType:jsonObject:options:headers:)``
 */
public struct Form<Headers: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let name: String
    let filename: String?
    let factory: PayloadFactory
    let headers: Headers

    // MARK: - Inits

    /**
     Creates a form with the given parameters.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - data: The data associated with the form field.

     > Note: This initializer is available when `Headers` is `EmptyProperty`.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .octetStream,
        data: Data
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: DataPayloadFactory(
                data: data,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    /**
     Creates a form with the given parameters.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - url: The URL associated with the form field.

     > Note: This initializer is available when `Headers` is `EmptyProperty`.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType,
        url: URL
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename ?? url.lastPathComponent,
            factory: FilePayloadFactory(
                url: url,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    /**
     Creates a form with the given parameters.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - verbatim: The verbatim data associated with the form field.

     > Note: This initializer is available when `Headers` is `EmptyProperty` and `Verbatim`
     conforms to `StringProtocol`.
     */
    public init<Verbatim: StringProtocol>(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .text,
        verbatim: Verbatim
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: StringPayloadFactory(
                verbatim: verbatim,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    /**
     Creates a form with the given parameters.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - value: The value to be encoded and associated with the form field.
        - encoder: The JSON encoder to use for encoding the value. Default is `JSONEncoder()`.

     > Note: This initializer is available when `Headers` is `EmptyProperty` and `Value`
     conforms to `Encodable`.
     */
    public init<Value: Encodable>(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
        value: Value,
        encoder: JSONEncoder = .init()
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: EncodablePayloadFactory(
                value,
                encoder: encoder,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    /**
     Creates a form with the given parameters.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - jsonObject: The JSON object to be associated with the form field.
        - options: The JSON writing options to use for serializing the JSON object. Default is `[]`.

     > Note: This initializer is available when `Headers` is `EmptyProperty`.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
        jsonObject: Any,
        options: JSONSerialization.WritingOptions = []
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: JSONPayloadFactory(
                jsonObject: jsonObject,
                options: options,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    /**
     Creates a form with the given parameters and custom headers.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - data: The data associated with the form field.
        - headers: A closure that returns custom headers for the form.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .octetStream,
        data: Data,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: DataPayloadFactory(
                data: data,
                contentType: contentType
            ),
            headers: headers()
        )
    }

    /**
     Creates a form with the given parameters and custom headers.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - url: The URL associated with the form field.
        - headers: A closure that returns custom headers for the form.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType,
        url: URL,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename ?? url.lastPathComponent,
            factory: FilePayloadFactory(
                url: url,
                contentType: contentType
            ),
            headers: headers()
        )
    }

    /**
     Creates a form with the given parameters and custom headers.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - verbatim: The verbatim data associated with the form field.
        - headers: A closure that returns custom headers for the form.

     > Note: This initializer is available when `Verbatim` conforms to `StringProtocol`.
     */
    public init<Verbatim: StringProtocol>(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .text,
        verbatim: Verbatim,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: StringPayloadFactory(
                verbatim: verbatim,
                contentType: contentType
            ),
            headers: headers()
        )
    }

    /**
     Creates a form with the given parameters and custom headers.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - value: The value to be encoded and associated with the form field.
        - encoder: The JSON encoder to use for encoding the value. Default is `JSONEncoder()`.
        - headers: A closure that returns custom headers for the form.

     > Note: This initializer is available when `Value` conforms to `Encodable`.
     */
    public init<Value: Encodable>(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
        value: Value,
        encoder: JSONEncoder = .init(),
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: EncodablePayloadFactory(
                value,
                encoder: encoder,
                contentType: contentType
            ),
            headers: headers()
        )
    }

    /**
     Creates a form with the given parameters and custom headers.

     - Parameters:
        - name: The name of the form field.
        - filename: The filename associated with the form field, if applicable.
        - contentType: The content type of the form field.
        - json: The JSON object to be associated with the form field.
        - options: The JSON writing options to use for serializing the JSON object. Default is `[]`.
        - headers: A closure that returns custom headers for the form.
     */
    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
        jsonObject: Any,
        options: JSONSerialization.WritingOptions = [],
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: JSONPayloadFactory(
                jsonObject: jsonObject,
                options: options,
                contentType: contentType
            ),
            headers: headers()
        )
    }

    private init(
        name: String,
        filename: String?,
        factory: PayloadFactory,
        headers: Headers
    ) {
        self.name = name
        self.filename = filename
        self.factory = factory
        self.headers = headers
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Form<Headers>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let additionalHeaders = try await headers(
            property: property,
            inputs: inputs
        )

        return .leaf(FormNode(
            chunkSize: inputs.environment.payloadChunkSize,
            item: FormItem(
                name: property.name,
                filename: property.filename,
                additionalHeaders: additionalHeaders.isEmpty ? nil : additionalHeaders,
                charset: inputs.environment.charset,
                urlEncoder: inputs.environment.urlEncoder,
                factory: property.factory
            )
        ))
    }

    // MARK: - Private static methods

    private static func headers(
        property: _GraphValue<Form<Headers>>,
        inputs: _PropertyInputs
    ) async throws -> HTTPHeaders {
        let output = try await Headers._makeProperty(
            property: property.headers,
            inputs: inputs
        )

        var headers = HTTPHeaders()

        for header in output.node.search(for: HeaderNode.self) {
            switch header.strategy {
            case .adding:
                headers.add(name: header.key, value: header.value)
            case .setting:
                headers.set(name: header.key, value: header.value)
            }
        }

        return headers
    }
}
// swiftlint:enable file_length
