//
//  Modifiers.KeyPath.swift
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

    public struct KeyPath<Content: Task>: TaskModifier where Content.Element == TaskResult<Data> {

        let keyPath: String

        init(_ keyPath: Swift.KeyPath<AbstractKeyPath, String>) {
            self.keyPath = AbstractKeyPath()[keyPath: keyPath]
        }

        public func task(_ task: Content) async throws -> TaskResult<Data> {
            let result = try await task.response()

            guard
                let dictonary = try JSONSerialization.jsonObject(with: result.data, options: []) as? [String: Any],
                let value = dictonary[keyPath]
            else { return result }

            return .init(
                response: result.response,
                data: try JSONSerialization.data(
                    withJSONObject: value,
                    options: .fragmentsAllowed
                )
            )
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func keyPath(_ keyPath: KeyPath<AbstractKeyPath, String>) -> ModifiedTask<Modifiers.KeyPath<Self>> {
        modify(Modifiers.KeyPath(keyPath))
    }
}
