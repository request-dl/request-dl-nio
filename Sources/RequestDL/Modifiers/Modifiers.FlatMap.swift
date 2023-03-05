//
//  Modifiers.FlatMap.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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

        private let flatMapHandler: (Result<Content.Element, Error>) throws -> NewElement

        init(flatMapHandler: @escaping (Result<Content.Element, Error>) throws -> NewElement) {
            self.flatMapHandler = flatMapHandler
        }

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
                    return try flatMapHandler(.success(original))
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
            return .success(.original(try await task.response()))
        } catch {
            return mapErrorIntoResult(error)
        }
    }

    func mapErrorIntoResult(_ error: Error) -> Result<Map, Error> {
        do {
            return .success(.processed(try flatMapHandler(.failure(error))))
        } catch {
            return .failure(error)
        }
    }
}

extension Task {

    /**
     Flat-maps the result of a `Task` to a new element type.

     - Parameters flatMapHandler: A closure that takes the result of the `Task` and transforms it to a new element type.
     - Returns: A new `Task` that returns the flat-mapped element of type `NewElement`.
     */
    public func flatMap<NewElement>(
        _ flatMapHandler: @escaping (Result<Element, Error>) throws -> NewElement
    ) -> ModifiedTask<Modifiers.FlatMap<Self, NewElement>> {
        modify(Modifiers.FlatMap(flatMapHandler: flatMapHandler))
    }
}
