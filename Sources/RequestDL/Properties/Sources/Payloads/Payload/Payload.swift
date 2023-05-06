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
@RequestActor
public struct Payload<Provider>: Property {

    private let isURLEncodedCompatible: Bool
    private let provider: Provider
    private let buffer: (Provider) -> BufferProtocol

    /**
     Initializes a `Payload` with a dictionary.

     - Parameters:
        - dictionary: A dictionary to be serialized.
        - options: Options for serializing the dictionary.
     */
    public init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions = .prettyPrinted
    ) where Provider == _DictionaryPayload {
        isURLEncodedCompatible = true
        provider = _DictionaryPayload(dictionary, options: options)
        buffer = { $0.buffer }
    }

    /**
     Initializes a `Payload` with an encodable value.

     - Parameters:
        - value: An encodable value to be serialized.
        - encoder: An encoder to use for the serialization.
     */
    public init<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = .init()
    ) where Provider == _EncodablePayload<T> {
        isURLEncodedCompatible = true
        provider = _EncodablePayload(value, encoder: encoder)
        buffer = { $0.buffer }
    }

    /**
     Initializes a `Payload` with a string.

     - Parameters:
        - string: A string to be used as the body data.
        - encoding: The encoding to use when converting the string to data.
     */
    public init(
        _ string: String,
        using encoding: String.Encoding = .utf8
    ) where Provider == _StringPayload {
        isURLEncodedCompatible = false
        provider = _StringPayload(string, using: encoding)
        buffer = { $0.buffer }
    }

    /**
     Initializes a `Payload` with raw `Data`.

     - Parameters:
        - data: The raw data to be used as the body.
     */
    public init(_ data: Data) where Provider == _DataPayload {
        isURLEncodedCompatible = false
        provider = _DataPayload(data)
        buffer = { $0.buffer }
    }

    /**
     Initializes a `Payload` with file `URL`.

     - Parameters:
        - fileURL: The file url to be used as the body.
     */
    public init(_ fileURL: URL) where Provider == _FilePayload {
        isURLEncodedCompatible = false
        provider = _FilePayload(fileURL)
        buffer = { $0.buffer }
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Payload {

    @RequestActor
    fileprivate struct Node: PropertyNode {

        let isURLEncodedCompatible: Bool
        let provider: Provider
        let buffer: (Provider) -> BufferProtocol
        let urlEncoder: URLEncoder

        func make(_ make: inout Make) async throws {
            guard
                isURLEncodedCompatible,
                isURLEncoded(make.request.headers),
                let data = buffer(provider).getData()
            else {
                make.request.body = Internals.Body(buffers: [buffer(provider)])
                return
            }

            let json = try jsonObject(data)

            switch json {
            case let value as [String: Any]:
                try makeDictionaryURLEncoded(value, in: &make)
            case let value as [Any]:
                try makeArrayURLEncoded(value, in: &make)
            default:
                make.request.body = Internals.Body(buffers: [buffer(provider)])
            }
        }
    }

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Payload<Provider>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            isURLEncodedCompatible: property.isURLEncodedCompatible,
            provider: property.provider,
            buffer: property.buffer,
            urlEncoder: inputs.environment.urlEncoder
        ))
    }
}

extension Payload.Node {

    func isURLEncoded(_ headers: Internals.Headers) -> Bool {
        headers.contains("x-www-form-urlencoded", forKey: "Content-Type")
    }

    func jsonObject(_ data: Data) throws -> Any {
        var readingOptions = JSONSerialization.ReadingOptions.fragmentsAllowed

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            readingOptions.insert(.json5Allowed)
        }

        return try JSONSerialization.jsonObject(with: data, options: readingOptions)
    }
}

extension Payload.Node {

    func makeDictionaryURLEncoded(_ value: [String: Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (key, value) in value {
            let encodedQueries = try urlEncoder.encode(value, forKey: key)
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    func makeArrayURLEncoded(_ value: [Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (index, value) in value.enumerated() {
            let encodedQueries = try urlEncoder.encode(value, forKey: "\(index)")
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    private func makeQueries(_ queries: [QueryItem], in make: inout Make) {
        let queries = queries.map { $0.build() }

        if outputPayloadInURL(make.request.method) {
            make.request.queries.append(contentsOf: queries)
        } else {
            make.request.body = Internals.Body(buffers: [
                Internals.DataBuffer(queries.joined().utf8)
            ])
        }
    }

    private func outputPayloadInURL(_ method: String?) -> Bool {
        guard let method else {
            return false
        }

        return ["GET", "HEAD"].first(where: {
            method.caseInsensitiveCompare($0) == .orderedSame
        }) != nil
    }
}
