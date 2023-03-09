/*
 See LICENSE for this package's licensing information.
*/

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
            print("[RequestDL]", "Missing identifier for a background session")
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
        print("[RequestDL]", """
        If a bug is found in Cache, handle urlSession(_:dataTask:willCacheResponse:completionHandler:)
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
        print("[RequestDL]", """
        If a bug is found in Cache, handle urlSession(_:dataTask:didReceive:completionHandler:)
        """)
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
