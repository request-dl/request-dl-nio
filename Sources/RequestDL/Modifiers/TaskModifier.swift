//
//  TaskModifier.swift
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

/**
 A protocol for modifying tasks and returning an element of a specific type.

 The `TaskModifier` protocol has two associated types: `Body` and `Element`. `Body`
 is the type of the task being modified, and `Element` is the type of the returned value after the modification.

 The `task` function takes in a `Body` task and returns an `Element` value after applying
 the modification logic.
 */
public protocol TaskModifier<Element> {

    /// The type of task being modified.
    associatedtype Body: Task

    /// The type of the returned element after modification.
    associatedtype Element

    /**
     Modifies the given task and returns an element of a specific type.

     - Parameter task: The task being modified.

     - Throws: An error of type `Error` if an error occurs during modification.

     - Returns: The modified element of type `Element`.
     */
    func task(_ task: Body) async throws -> Element
}
