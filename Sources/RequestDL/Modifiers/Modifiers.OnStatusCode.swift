//
//  Modifiers.OnStatusCode.swift
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

    public struct OnStatusCode<Content: Task>: TaskModifier where Content.Element: TaskResultPrimitive {

        private let contains: (Int) -> Bool
        private let mapHandler: (Content.Element) throws -> Void

        init(contains: @escaping (Int) -> Bool, map: @escaping (Content.Element) throws -> Void) {
            self.contains = contains
            self.mapHandler = map
        }

        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.response()

            guard
                let response = result.response as? HTTPURLResponse,
                contains(response.statusCode)
            else { return result }

            try mapHandler(result)
            return result
        }
    }
}

extension Task where Element: TaskResultPrimitive {

    private func onStatusCode(
        _ map: @escaping (Element) throws -> Void,
        contains: @escaping (Int) -> Bool
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        modify(.init(
            contains: contains,
            map: map
        ))
    }

    public func onStatusCode(
        _ statusCode: Range<Int>,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    public func onStatusCode(
        _ statusCode: Set<Int>,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    public func onStatusCode(
        _ statusCode: Int,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode == $0
        }
    }
}
