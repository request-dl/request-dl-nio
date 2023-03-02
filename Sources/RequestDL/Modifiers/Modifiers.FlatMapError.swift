//
//  Modifiers.FlatMapError.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
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

    public struct FlatMapError<Content: Task>: TaskModifier {

        // swiftlint:disable nesting
        public typealias Element = Content.Element

        let flatMapErrorHandler: (Error) throws -> Void

        init(flatMapErrorHandler: @escaping (Error) throws -> Void) {
            self.flatMapErrorHandler = flatMapErrorHandler
        }

        public func task(_ task: Content) async throws -> Element {
            do {
                return try await task.response()
            } catch {
                try flatMapErrorHandler(error)
                throw error
            }
        }
    }
}

extension Task {

    public func flatMapError(
        _ flatMapErrorHandler: @escaping (Error) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        modify(Modifiers.FlatMapError(flatMapErrorHandler: flatMapErrorHandler))
    }

    public func flatMapError<Failure: Error>(
        _ type: Failure.Type,
        _ flatMapErrorHandler: @escaping (Failure) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        flatMapError {
            if let error = $0 as? Failure {
                try flatMapErrorHandler(error)
            }
        }
    }
}
