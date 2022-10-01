//
//  Timeout.swift
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

public struct Timeout: Request {

    public typealias Body = Never

    let timeout: TimeInterval
    let source: Source

    public init(_ timeout: TimeInterval, for source: Source = .all) {
        self.timeout = timeout
        self.source = source
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Timeout: PrimitiveRequest {

    struct Object: NodeObject {

        let timeout: TimeInterval
        let source: Source

        init(_ timeout: TimeInterval, _ source: Source) {
            self.timeout = timeout
            self.source = source
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            if source.contains(.request) {
                configuration.configuration.timeoutIntervalForRequest = timeout
            }

            if source.contains(.resource) {
                configuration.configuration.timeoutIntervalForResource = timeout
            }
        }
    }

    func makeObject() -> Object {
        .init(timeout, source)
    }
}
