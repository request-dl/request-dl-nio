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
     - `Element`: The type to decode the data into.
     - `Output`: The decoded result.

     The `Decode` modifier can be used with any `Task` whose `Element` is of type
     `TaskResult<Data>` or `Data`. It expects a `Decodable` type to be specified as
     the `Element` type it will decode the data into.

     The decoding operation is performed using a `JSONDecoder`. By default, the decoding is
     performed assuming that the data is in plain format, i.e., not an array or dictionary.
     */
    public struct Decode<Content: Task, Element: Decodable, Output: Sendable>: TaskModifier {

        // MARK: - Internal properties

        let type: Element.Type
        let decoder: JSONDecoder

        // MARK: - Private properties

        fileprivate let data: @Sendable (Content.Element) -> Data
        fileprivate let output: @Sendable (Content.Element, Element) -> Output

        // MARK: - Public methods

        /**
         Decodes the data of the specified `Task` instance into an instance of the `Element`
         type specified during initialization.

         - Parameter task: The `Task` instance whose data is to be decoded.
         - Returns: A `Output` instance containing the decoded data.
         - Throws: If the decoding operation fails.
         */
        public func task(_ task: Content) async throws -> Output {
            let result = try await task.result()

            return try output(result, decoder.decode(type, from: data(result)))
        }
    }
}

// MARK: - Task extensions

extension Task {

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
    ) -> ModifiedTask<Modifiers.Decode<Self, T, TaskResult<T>>>
    where Element == TaskResult<Data> {
        modify(Modifiers.Decode(
            type: type,
            decoder: decoder,
            data: \.payload,
            output: {
                TaskResult(
                    head: $0.head,
                    payload: $1
                )
            }
        ))
    }

    /**
     Returns a new instance of `ModifiedTask` that applies the `Decode` modifier to the original
     `Task`.

     - Parameters:
        - type: The type to decode the data into.
        - decoder: The `JSONDecoder` instance to use for the decoding operation.
     - Returns: A new instance of `ModifiedTask` with the `Decode` modifier applied.
     */
    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T, T>>
    where Element == Data {
        modify(Modifiers.Decode(
            type: type,
            decoder: decoder,
            data: { $0 },
            output: { $1 }
        ))
    }
}
