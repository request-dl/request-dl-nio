//
//  DownloadCertificate.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation
@testable import RequestDL

struct DownloadCertificate {

    private let url: String
    private let delegate: Delegate

    init(from url: String) {
        self.url = url
        self.delegate = Delegate()
    }

    func download() async throws -> Data {
        guard let url = URL(string: url) else {
            throw DownloadingError.invalidURL
        }

        let request = URLRequest(url: url)
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )

        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            _ = try? await session.data(for: request, delegate: delegate)
        } else {
            await withUnsafeContinuation { continuation in
                session.dataTask(
                    with: request,
                    completionHandler: { _, _, _ in
                        continuation.resume()
                    }
                )
            }
        }

        session.finishTasksAndInvalidate()

        if let certificate = delegate.certificate {
            return certificate
        }

        throw DownloadingError.invalidCertificate
    }
}

extension DownloadCertificate {

    class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

        var certificate: Data?

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard let secTrust = challenge.protectionSpace.serverTrust else {
                return (.performDefaultHandling, nil)
            }

            certificate = secTrust.certificates.first?.data
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}

extension DownloadCertificate {

    enum DownloadingError: Error {
        case invalidURL
        case invalidCertificate
    }
}
