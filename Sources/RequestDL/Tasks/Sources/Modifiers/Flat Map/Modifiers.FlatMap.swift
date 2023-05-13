/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A modifier that allows flat-mapping the result of a `Task` to a new element type.

     `Content` is the type of the original `Task`, and `NewElement` is the type of the new
     element that the result will be flat-mapped to.

     Example:

     ```swift
     DataTask { ... }
         .flatMap { result in
             // transform result to new element type
         }
     ```
     */
    public struct FlatMap<Content: Task, NewElement>: TaskModifier {

        let transform: (Result<Content.Element, Error>) throws -> NewElement

        /**
         Transforms the result of a `Task` to a new element type.

         - Parameter task: The original `Task`.
         - Throws: An error if the transformation fails.
         - Returns: The result of the transformation.
         */
        public func task(_ task: Content) async throws -> NewElement {
            switch await mapResponseIntoResult(task) {
            case .failure(let error):
                throw error
            case .success(let map):
                switch map {
                case .processed(let mapped):
                    return mapped
                case .original(let original):
                    return try transform(.success(original))
                }
            }
        }
    }
}

private extension Modifiers.FlatMap {

    enum Map {
        case original(Content.Element)
        case processed(NewElement)
    }
}

private extension Modifiers.FlatMap {

    func mapResponseIntoResult(_ task: Content) async -> Result<Map, Error> {
        do {
            return .success(.original(try await task.result()))
        } catch {
            return mapErrorIntoResult(error)
        }
    }

    func mapErrorIntoResult(_ error: Error) -> Result<Map, Error> {
        do {
            return .success(.processed(try transform(.failure(error))))
        } catch {
            return .failure(error)
        }
    }
}

extension Task {

    /**
     Flat-maps the result of a `Task` to a new element type.

     - Parameter transform: A closure that takes the result of the `Task` and transforms it to a new element type.
     - Returns: A new `Task` that returns the flat-mapped element of type `NewElement`.
     */
    public func flatMap<NewElement>(
        _ transform: @escaping (Result<Element, Error>) throws -> NewElement
    ) -> ModifiedTask<Modifiers.FlatMap<Self, NewElement>> {
        modify(Modifiers.FlatMap(transform: transform))
    }
}
