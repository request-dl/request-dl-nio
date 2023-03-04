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

/**
 A representation of the server trust, that contains one or more certificates that the server uses to identify itself to the client.

 Use the `ServerTrust` structure to configure the server trust policy of a URL session. The server trust policy determines how to validate the server's TLS certificate chain.

 You can initialize a `ServerTrust` instance with one or more `Certificate` instances that identify the trusted certificates of the server.

 - Note: A `ServerTrust` instance should only contain trusted certificates of the server.
 */
public struct ServerTrust: Property {

    private let certificates: [Certificate]

    /**
     Initializes a `ServerTrust` instance with the given certificate.

     - Parameter certificate: The `Certificate` that identifies the trusted certificate of the server.

     */
    public init(_ certificate: Certificate) {
        self.certificates = [certificate]
    }

    /**
     Initializes a `ServerTrust` instance with an array of certificates.

     - Parameter certificates: An array of `Certificate` instances that identify the trusted certificates of the server.
     */
    public init(_ certificate: Certificate...) {
        self.certificates = certificate
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension ServerTrust: PrimitiveProperty {

    struct Object: NodeObject {

        private let certificates: [Certificate]

        public init(_ certificates: [Certificate]) {
            self.certificates = certificates
        }

        func makeProperty(_ configuration: MakeConfiguration) {
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
