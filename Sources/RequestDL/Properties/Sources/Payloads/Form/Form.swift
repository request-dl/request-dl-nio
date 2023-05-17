/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Form<Headers: Property>: Property {

    enum Source {
        case data(Data)
        case url(URL)
        case string(String)
        case encoded(() throws -> Data)
        case json(Any, JSONSerialization.WritingOptions)
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let name: String
    let filename: String?
    let contentType: ContentType?
    let source: Source
    let headers: Headers

    // MARK: - Inits

    public init(
        _ data: Data,
        name: String,
        filename: String? = nil,
        contentType: ContentType? = nil
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .data(data),
            headers: EmptyProperty()
        )
    }

    public init(
        _ url: URL,
        name: String,
        filename: String? = nil,
        contentType: ContentType
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .url(url),
            headers: EmptyProperty()
        )
    }

    public init<S: StringProtocol>(
        _ string: S,
        name: String,
        filename: String? = nil,
        contentType: ContentType? = nil
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .string(String(string)),
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
            contentType: contentType,
            source: .encoded { try encoder.encode(value) },
            headers: EmptyProperty()
        )
    }

    public init(
        _ json: Any,
        options: JSONSerialization.WritingOptions,
        name: String,
        filename: String? = nil,
        contentType: ContentType = .json
    ) where Headers == EmptyProperty {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .json(json, options),
            headers: EmptyProperty()
        )
    }

    public init(
        _ data: Data,
        name: String,
        filename: String? = nil,
        contentType: ContentType? = nil,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .data(data),
            headers: headers()
        )
    }

    public init(
        _ url: URL,
        name: String,
        filename: String? = nil,
        contentType: ContentType,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .url(url),
            headers: headers()
        )
    }

    public init<S: StringProtocol>(
        _ string: S,
        name: String,
        filename: String? = nil,
        contentType: ContentType? = nil,
        @PropertyBuilder headers: () -> Headers
    ) {
        self.init(
            name: name,
            filename: filename,
            contentType: contentType,
            source: .string(String(string)),
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
            contentType: contentType,
            source: .encoded { try encoder.encode(value) },
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
            contentType: contentType,
            source: .json(json, options),
            headers: headers()
        )
    }

    private init(
        name: String,
        filename: String?,
        contentType: ContentType?,
        source: Source,
        headers: Headers
    ) {
        self.name = name
        self.filename = filename
        self.contentType = contentType
        self.source = source
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

        switch property.source {
        case .data(let data):
            return .leaf(makeItemNode(
                property: property,
                headers: additionalHeaders,
                buffer: Internals.DataBuffer(data),
                environment: inputs.environment
            ))
        case .url(let url):
            return .leaf(makeItemNode(
                property: property,
                headers: additionalHeaders,
                buffer: Internals.FileBuffer(url),
                environment: inputs.environment
            ))
        case .string(let string):
            return .leaf(makeItemNode(
                property: property,
                headers: additionalHeaders,
                buffer: Internals.DataBuffer(string),
                environment: inputs.environment
            ))
        case .encoded(let encoder):
            return try .leaf(makeItemNode(
                property: property,
                headers: additionalHeaders,
                buffer: Internals.DataBuffer(encoder()),
                environment: inputs.environment
            ))
        case .json(let json, let options):
            return try .leaf(makeItemNode(
                property: property,
                headers: additionalHeaders,
                buffer: Internals.DataBuffer(JSONSerialization.data(
                    withJSONObject: json,
                    options: options
                )),
                environment: inputs.environment
            ))
        }
    }

    // MARK: - Private static methods

    private static func headers(
        property: _GraphValue<Form<Headers>>,
        inputs: _PropertyInputs
    ) async throws -> Internals.Headers {
        let output = try await Headers._makeProperty(
            property: property.headers,
            inputs: inputs
        )

        return Internals.Headers(
            output.node.search(for: RequestDL.Headers.Node.self)
                .lazy
                .filter { !$0.value.isEmpty }
                .map { ($0.key, $0.value) }
        )
    }

    private static func makeItemNode(
        property: _GraphValue<Form<Headers>>,
        headers: Internals.Headers,
        buffer: Internals.AnyBuffer,
        environment environmentValues: EnvironmentValues
    ) -> FormNode {
        FormNode(environmentValues.payloadPartLength) {
            MultipartItem(
                name: property.name,
                filename: property.filename,
                contentType: property.contentType,
                additionalHeaders: headers.isEmpty ? nil : headers,
                data: buffer
            )
        }
    }
}
