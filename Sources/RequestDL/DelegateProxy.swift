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
    private var didFinishDownloadingToLocation: ((URL) -> Void)?

    override init() {}

    func onDidReceiveChallenge(
        _ challengeHandler: @escaping ReceiveChallengeHandler
    ) {
        let old = didReceiveChallengeHandler
        didReceiveChallengeHandler = {
            (old?($0) ?? []) + [challengeHandler($0)]
        }
    }

    func onDidFinishDownloadingToLocation(
        _ locationHandler: @escaping (URL) -> Void
    ) {
        let old = didFinishDownloadingToLocation
        didFinishDownloadingToLocation = {
            old?($0)
            locationHandler($0)
        }
    }
}

extension DelegateProxy: URLSessionDelegate {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            BackgroundService.shared.completionHandler?()
            BackgroundService.shared.completionHandler = nil
        }
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
        print("[Request]", "If a bug is found in Cache, handle DelegateProxy._:dataTask:willCacheResponse:completionHandler:")
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

extension DelegateProxy: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        didFinishDownloadingToLocation?(location)
    }
}
