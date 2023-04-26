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
public struct Payload<Provider>: Property {

    enum Source {
        case file(Internals.FileBuffer)
        case data(Internals.DataBuffer)
    }

    private let provider: Provider
    private let source: (Provider) -> Source

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
        provider = _DictionaryPayload(dictionary, options: options)
        source = { .data($0.buffer) }
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
        provider = _EncodablePayload(value, encoder: encoder)
        source = { .data($0.buffer) }
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
        provider = _StringPayload(string, using: encoding)
        source = { .data($0.buffer) }
    }

    /**
     Initializes a `Payload` with raw `Data`.

     - Parameters:
        - data: The raw data to be used as the body.
     */
    public init(_ data: Data) where Provider == _DataPayload {
        provider = _DataPayload(data)
        source = { .data($0.buffer) }
    }

    /**
     Initializes a `Payload` with file `URL`.

     - Parameters:
        - fileURL: The file url to be used as the body.
     */
    public init(_ fileURL: URL) where Provider == _FilePayload {
        provider = _FilePayload(fileURL)
        source = { .file($0.buffer) }
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Payload {

    struct Node: PropertyNode {

        private let source: () -> Source

        fileprivate init(_ source: @escaping () -> Source) {
            self.source = source
        }

        func make(_ make: inout Make) async throws {
            switch source() {
            case .data(let dataBuffer):
                make.request.body = Internals.Body(buffers: [dataBuffer])
            case .file(let fileBuffer):
                make.request.body = Internals.Body(buffers: [fileBuffer])
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Payload<Provider>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertIfNeeded()
        return .init(Leaf(Node {
            property.source(property.provider)
        }))
    }
}
