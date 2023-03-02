//
//  ServerTrust.swift
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
import Security
import CommonCrypto

public struct ServerTrust: Request {

    private let certificates: [Certificate]

    public init(_ certificate: Certificate) {
        self.certificates = [certificate]
    }

    public init(_ certificate: Certificate...) {
        self.certificates = certificate
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension ServerTrust: PrimitiveRequest {

    struct Object: NodeObject {

        private let certificates: [Certificate]

        public init(_ certificates: [Certificate]) {
            self.certificates = certificates
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            configuration.delegate.onDidReceiveChallenge {
                receivedChallenge($0)
            }
        }
    }

    func makeObject() -> Object {
        Object(certificates)
    }
}

private extension ServerTrust.Object {

    func receivedChallenge(_ challenge: URLAuthenticationChallenge) -> DelegateProxy.ChallengeCredential {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return (.rejectProtectionSpace, nil)
        }

        var error: CFError?

        guard
            let serverTrust = challenge.protectionSpace.serverTrust,
            SecTrustEvaluateWithError(serverTrust, &error),
            let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0)
        else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let serverCertificateDER = SecCertificateCopyData(serverCertificate)

        guard let serverCertificateRawPointer = CFDataGetBytePtr(serverCertificateDER) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let serverCertificateData = Data(
            bytes: serverCertificateRawPointer,
            count: CFDataGetLength(serverCertificateDER)
        )

        for certificate in certificates {
            guard
                let clientCertificatePath = certificate.bundle.path(forResource: certificate.name, ofType: "cer"),
                let clientCertificateData = NSData(contentsOfFile: clientCertificatePath)
            else { continue }

            if serverCertificateData == clientCertificateData as Data {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        }

        return (.cancelAuthenticationChallenge, nil)
    }
}
