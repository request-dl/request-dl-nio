//
//  GroupTask.swift
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

public struct GroupTask<Data: Collection, Content: Task>: Task {

    private let data: Data
    private let map: (Data.Element) -> Content

    public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.map = content
    }
}

extension GroupTask {

    public func response() async throws -> [GroupResult<Data.Element, Content.Element>] {
        try await withThrowingTaskGroup(of: GroupResult<Data.Element, Content.Element>.self) { group in
            for element in data {
                group.addTask {
                    let data = try await map(element).response()
                    return .init(id: element, result: data)
                }
            }

            var stack = [GroupResult<Data.Element, Content.Element>]()

            for try await element in group {
                stack.append(element)
            }

            return stack
        }
    }
}

public struct GroupResult<ID, Element> {

    public let id: ID
    public let result: Element

    init(id: ID, result: Element) {
        self.id = id
        self.result = result
    }
}
