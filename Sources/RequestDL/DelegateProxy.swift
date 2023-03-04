//
//  DelegateProxy.swift
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

class DelegateProxy: NSObject {

    typealias ChallengeCredential = (
        URLSession.AuthChallengeDisposition,
        URLCredential?
    )

    typealias ReceiveChallengeHandler = (
        URLAuthenticationChallenge
    ) -> ChallengeCredential

    private var didReceiveChallengeHandler: ((URLAuthenticationChallenge) -> [ChallengeCredential])?

    override init() {}

    func onDidReceiveChallenge(
        _ challengeHandler: @escaping ReceiveChallengeHandler
    ) {
        let old = didReceiveChallengeHandler
        didReceiveChallengeHandler = {
            (old?($0) ?? []) + [challengeHandler($0)]
        }
    }
}

extension DelegateProxy: URLSessionDelegate {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else {
            print("[Request]", "Missing identifier for a background session")
            return
        }

        BackgroundService.shared.completionHandler?(identifier)
    }
}

extension DelegateProxy: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        #if DEBUG
        print("[Request]", """
        If a bug is found in Cache, handle DelegateProxy._:dataTask:willCacheResponse:completionHandler:
        """)
        #endif
        completionHandler(proposedResponse)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        #if DEBUG
        print("[Request]", "If a bug is found in Cache, handle DelegateProxy._:dataTask:didReceive:completionHandler:")
        #endif
        completionHandler(.allow)
    }
}

extension DelegateProxy: URLSessionTaskDelegate {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {

        let results = didReceiveChallengeHandler?(challenge) ?? []

        if results.contains(where: { $0.0 == .cancelAuthenticationChallenge }) {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }

        if let credentials = results.first(where: { $0.0 == .useCredential }) {
            return completionHandler(credentials.0, credentials.1)
        }

        if results.contains(where: { $0.0 == .rejectProtectionSpace }) {
            return completionHandler(.rejectProtectionSpace, nil)
        }

        return completionHandler(.performDefaultHandling, nil)
    }
}
