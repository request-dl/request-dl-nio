//
//  Target.swift
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

public protocol Target {

    associatedtype HTTPSession: Request
    associatedtype Path: Request
    associatedtype HTTPMethod: Request
    associatedtype HTTPHeaders: Request
    associatedtype Body: Request

    var session: HTTPSession { get }
    var path: Path { get }
    var method: HTTPMethod { get }
    var headers: HTTPHeaders { get }
    var body: Body { get }
}

public extension Target {

    var session: some Request {
        Session(.default)
    }

    var method: some Request {
        Method(.get)
    }

    var headers: some Request {
        Group {
            Headers.Accept(.json)
            Headers.ContentType(.json)
        }
    }

    var body: some Request {
        EmptyRequest()
    }
}

extension Target {

    @RequestBuilder
    func reduced() -> some Request {
        session
        path
        method
        headers
        body
    }
}
