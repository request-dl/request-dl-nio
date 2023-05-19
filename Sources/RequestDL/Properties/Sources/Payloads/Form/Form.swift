/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType,
        url: URL
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: FilePayloadFactory(
                url: url,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

    public init<Verbatim: StringProtocol>(
        name: String,
        filename: String? = nil,
        contentType: ContentType,
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

    public init<Value: Encodable>(
        _ value: Value,
        encoder: JSONEncoder = .init(),
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json
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

    public init(
        _ json: Any,
        options: JSONSerialization.WritingOptions = [],
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            factory: JSONPayloadFactory(
                jsonObject: json,
                options: options,
                contentType: contentType
            ),
            headers: EmptyProperty()
        )
    }

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

    public init(
        name: String,
        filename: String? = nil,
        contentType: ContentType,
        url: URL,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: FilePayloadFactory(
                url: url,
                contentType: contentType
            ),
            headers: headers()
        )
    }

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

    public init<Value: Encodable>(
        _ value: Value,
        encoder: JSONEncoder = .init(),
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
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

    public init(
        _ json: Any,
        options: JSONSerialization.WritingOptions,
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            factory: JSONPayloadFactory(
                jsonObject: json,
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

        return try .leaf(FormNode(
            fragmentLength: inputs.environment.payloadPartLength,
            item: FormItem(
                name: property.name,
                filename: property.filename,
                additionalHeaders: additionalHeaders.isEmpty ? nil : additionalHeaders,
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

        return HTTPHeaders(
            output.node.search(for: RequestDL.Headers.Node.self)
                .lazy
                .filter { !$0.value.isEmpty }
                .map { ($0.key, $0.value) }
        )
    }
}
