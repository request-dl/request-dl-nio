//
//  Session.swift
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

public struct Session: Request {

    public typealias Body = Never

    private let configuration: Configuration
    private let queue: OperationQueue?

    public init(_ configuration: Configuration) {
        self.configuration = configuration
        self.queue = nil
    }

    public init(_ configuration: Configuration, queue: OperationQueue) {
        self.configuration = configuration
        self.queue = queue
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Session {

    public enum Configuration {

        case `default`
        case ephemeral

        /// [BETA]: Report in case of errors
        case background(String)

        var sessionConfiguration: URLSessionConfiguration {
            switch self {
            case .default:
                return .default
            case .ephemeral:
                return .ephemeral
            case .background(let identifier):
                return .background(withIdentifier: identifier)
            }
        }
    }
}

extension Session: PrimitiveRequest {

    struct Object: NodeObject {

        let configuration: Configuration
        let queue: OperationQueue?

        init(_ configuration: Configuration, _ queue: OperationQueue?) {
            self.configuration = configuration
            self.queue = queue
        }

        func makeRequest(_ configuration: RequestConfiguration) {}
    }

    func makeObject() -> Object {
        .init(configuration, queue)
    }
}
