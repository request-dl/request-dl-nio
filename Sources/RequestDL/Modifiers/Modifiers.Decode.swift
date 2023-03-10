/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A `TaskModifier` that decodes the data returned by the `Task` into a specified type
     using a `JSONDecoder`.

     Generic types:

     - `Content`: The type of the original `Task` being modified.
     - `Element`: The type to decode the result data into.

     The `Decode` modifier can be used with any `Task` whose `Element` is of type
     `TaskResult<Data>`. It expects a `Decodable` type to be specified as the `Element`
     type it will decode the result data into.

     The decoding operation is performed using a `JSONDecoder`. By default, the decoding is
     performed assuming that the data is in plain format, i.e., not an array or dictionary.
     */
    public struct Decode<Content: Task, Element: Decodable>: TaskModifier where Content.Element == TaskResult<Data> {

        let type: Element.Type
        let decoder: JSONDecoder
        private let contentType: DecodeContentType

        fileprivate init(_ type: Element.Type, decoder: JSONDecoder, contentType: DecodeContentType) {
            self.type = type
            self.decoder = decoder
            self.contentType = contentType
        }

        /**
         Decodes the result data of the specified `Task` instance into an instance of the
         `Element` type specified during initialization.

         - Parameter task: The `Task` instance whose result data is to be decoded.
         - Returns: A `TaskResult` instance containing the decoded data.
         - Throws: If the decoding operation fails.
         */
        public func task(_ task: Content) async throws -> TaskResult<Element> {
            let result = try await task.result()

            return .init(
                response: result.response,
                data: try decoder.decode(type, from: flatMap(result.data))
            )
        }
    }
}

extension Modifiers.Decode {

    private func flatMap(_ data: Data) -> Data {
        switch contentType {
        case .plain:
            return data
        case .array:
            return data.isEmpty ? "[]".data(using: .utf8) ?? data : data
        case .dictionary:
            return data.isEmpty ? "{}".data(using: .utf8) ?? data : data
        }
    }
}

extension Task where Element == TaskResult<Data> {

    /**
     Returns a new instance of `ModifiedTask` that applies the `Decode` modifier to the original
     `Task`.

     - Parameters:
        - type: The type to decode the result data into.
        - decoder: The `JSONDecoder` instance to use for the decoding operation.
     - Returns: A new instance of `ModifiedTask` with the `Decode` modifier applied.
     */
    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .plain))
    }

    /**
     Returns a new instance of `ModifiedTask` that applies the `Decode` modifier to the original
     `Task`, assuming the result data is an array.

     - Parameters:
        - type: The type to decode the result data into.
        - decoder: The `JSONDecoder` instance to use for the decoding operation.
     - Returns: A new instance of `ModifiedTask` with the `Decode` modifier applied.
     */
    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> where T: Collection {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .array))
    }

    /**
     Returns a new instance of `ModifiedTask` that applies the `Decode` modifier to the original
     `Task`, assuming the result data is a dictionary.

     - Parameters:
        - type: The type to decode the result data into.
        - decoder: The `JSONDecoder` instance to use for the decoding operation.
     - Returns: A new instance of `ModifiedTask` with the `Decode` modifier applied.
     */
    public func decode<Key: Decodable, Value: Decodable>(
        _ type: [Key: Value].Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, [Key: Value]>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .dictionary))
    }
}

private enum DecodeContentType {
    case plain
    case array
    case dictionary
}
