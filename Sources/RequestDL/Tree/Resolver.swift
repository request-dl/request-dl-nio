//
//  Resolver.swift
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

struct Resolver<Content: Request> {

    private let request: Content

    init(_ request: Content) {
        self.request = request
    }

    private func resolve() async -> Context {
        let context = Context(RootNode())
        await Content.makeRequest(request, context)
        return context
    }

    func make(_ delegate: DelegateProxy) async -> (URLSession, URLRequest) {
        let context = await resolve()

        guard let object = context.find(Url.Object.self) else {
            fatalError()
        }

        let sessionObject = context.find(Session.Object.self)

        let configuration = RequestConfiguration(
            request: URLRequest(url: object.url),
            configuration: sessionObject?.configuration ?? .default,
            delegate: delegate
        )

        context.make(configuration)

        let session = URLSession(
            configuration: configuration.configuration,
            delegate: delegate,
            delegateQueue: sessionObject?.queue
        )

        return (session, configuration.request)
    }
}

extension Resolver {

    func debugPrint() async {
        let context = await resolve()
        context.debug()
    }
}
