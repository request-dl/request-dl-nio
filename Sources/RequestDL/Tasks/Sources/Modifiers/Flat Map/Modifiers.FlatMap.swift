/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A modifier that allows flat-mapping the result of a `RequestTask` to a new element type.

     `Content` is the type of the original `RequestTask`, and `NewElement` is the type of the new
     element that the result will be flat-mapped to.

     ```swift
     DataTask { ... }
         .flatMap { result in
             // transform result to new element type
         }
     ```
     */
    public struct FlatMap<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        enum Map: Sendable {
            case original(Input)
            case processed(Output)
        }

        // MARK: - Internal properties

        let transform: @Sendable (Result<Input, Error>) async throws -> Output

        // MARK: - Public methods

        /**
         Transforms the result of a `RequestTask` to a new element type.

         - Parameter task: The original `RequestTask`.
         - Throws: An error if the transformation fails.
         - Returns: The result of the transformation.
         */
        public func body(_ task: Content) async throws -> Output {
            switch await mapResponseIntoResult(task) {
            case .failure(let error):
                throw error
            case .success(let map):
                switch map {
                case .processed(let mapped):
                    return mapped
                case .original(let original):
                    return try await transform(.success(original))
                }
            }
        }

        // MARK: - Private methods

        private func mapResponseIntoResult(_ task: Content) async -> Result<Map, Error> {
            do {
                return .success(.original(try await task.result()))
            } catch {
                return await mapErrorIntoResult(error)
            }
        }

        private func mapErrorIntoResult(_ error: Error) async -> Result<Map, Error> {
            do {
                return try await .success(.processed(transform(.failure(error))))
            } catch {
                return .failure(error)
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Flat-maps the result of a `RequestTask` to a new element type.

     - Parameter transform: A closure that takes the result of the `RequestTask` and transforms
     it to a new element type.
     - Returns: A new `RequestTask` that returns the flat-mapped element of type `NewElement`.
     */
    public func flatMap<NewElement>(
        _ transform: @escaping @Sendable (Result<Element, Error>) async throws -> NewElement
    ) -> ModifiedRequestTask<Modifiers.FlatMap<Element, NewElement>> {
        modifier(Modifiers.FlatMap(transform: transform))
    }
}
