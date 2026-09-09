//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONDecoder
#endif

extension Modifiers {

    ///
    /// A `RequestTaskModifier` that decodes the data returned by the `RequestTask` into an
    /// optional instance of a specified type, treating an empty body as `nil` instead of
    /// attempting to run it through `JSONDecoder`.
    ///
    /// Unlike ``Decode``, which always hands the raw bytes to `JSONDecoder` -- and therefore
    /// fails with an opaque "the given data was not valid JSON" on an empty body -- this is meant
    /// for endpoints that may legitimately answer with no body at all, such as a `204 No Content`
    /// or `205 Reset Content` response to a `DELETE`/`PUT`.
    ///
    public struct DecodeIfPresent<Input: Sendable, Element: Decodable & Sendable, Output: Sendable>: RequestTaskModifier
    {

        // MARK: - Internal properties

        let type: Element.Type
        let decoder: JSONDecoder

        // MARK: - Private properties

        fileprivate let data: @Sendable (Input) -> Data
        fileprivate let output: @Sendable (Input, Element?) -> Output

        // MARK: - Public methods

        ///
        /// Decodes the data of the specified `RequestTask` instance into an instance of the
        /// `Element` type specified during initialization, or `nil` when the body is empty.
        ///
        /// - Parameter task: The `RequestTask` instance whose data is to be decoded.
        /// - Returns: A `Output` instance containing the decoded data, or `nil` when the body was
        /// empty.
        /// - Throws: If the body is non-empty and the decoding operation fails.
        ///
        public func body(_ task: Content) async throws -> Output {
            let result = try await task.result()
            let bytes = data(result)

            guard !bytes.isEmpty else {
                return output(result, nil)
            }

            return output(result, try decoder.decode(type, from: bytes))
        }
    }
}

// MARK: - RequestTask extensions

extension RequestTask {

    ///
    /// Returns a new instance of `ModifiedTask` that applies the `DecodeIfPresent` modifier to
    /// the original `RequestTask`, decoding an empty body as `nil` rather than throwing.
    ///
    /// - Parameters:
    ///    - type: The type to decode the result data into when the body is non-empty.
    ///    - decoder: The `JSONDecoder` instance to use for the decoding operation.
    /// - Returns: A new instance of `ModifiedTask` with the `DecodeIfPresent` modifier applied.
    ///
    public func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedRequestTask<Modifiers.DecodeIfPresent<Element, T, TaskResult<T?>>>
    where Element == TaskResult<Data> {
        modifier(
            Modifiers.DecodeIfPresent(
                type: type,
                decoder: decoder,
                data: \.payload,
                output: {
                    TaskResult(
                        head: $0.head,
                        payload: $1
                    )
                }
            )
        )
    }

    ///
    /// Returns a new instance of `ModifiedTask` that applies the `DecodeIfPresent` modifier to
    /// the original `RequestTask`, decoding an empty body as `nil` rather than throwing.
    ///
    /// - Parameters:
    ///    - type: The type to decode the data into when the body is non-empty.
    ///    - decoder: The `JSONDecoder` instance to use for the decoding operation.
    /// - Returns: A new instance of `ModifiedTask` with the `DecodeIfPresent` modifier applied.
    ///
    public func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedRequestTask<Modifiers.DecodeIfPresent<Element, T, T?>>
    where Element == Data {
        modifier(
            Modifiers.DecodeIfPresent(
                type: type,
                decoder: decoder,
                data: { $0 },
                output: { $1 }
            )
        )
    }
}
