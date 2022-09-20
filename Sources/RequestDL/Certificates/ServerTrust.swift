import Foundation
import Security
import CommonCrypto

/**

 To get the privateKey:
 ```
 openssl s_client -connect www.google.com:443 -showcerts < /dev/null | openssl x509 -outform DER > google.der
 python -sBc "from __future__ import print_function;import hashlib;print(hashlib.sha256(open('google.der','rb').read()).digest(), end='')" | base64
 ```

 To get the publicKey:
 ```
 openssl x509 -pubkey -noout -in google.der -inform DER | openssl rsa -outform DER -pubin -in /dev/stdin 2>/dev/null > googlekey.der
 python -sBc "from __future__ import print_function;import hashlib;print(hashlib.sha256(open('googlekey.der','rb').read()).digest(), end='')" | base64
 ```
 */
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

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            delegate.onDidReceiveChallenge {
                receivedChallenge($0)
            }
        }
    }

    func makeObject() -> Object {
        Object(certificates)
    }
}

private extension ServerTrust.Object {

    var rsa2048Asn1Header: [UInt8] {
        [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]
    }

    func sha256(data: Data) -> String {
        var keyWithHeader = Data(rsa2048Asn1Header)
        keyWithHeader.append(data)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        keyWithHeader.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(keyWithHeader.count), &hash)
        }

        return Data(hash).base64EncodedString()
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

        for certificate in certificates {
            switch certificate.type {
            case .byPrivateKey:
                let serverCertificateData = SecCertificateCopyData(serverCertificate)
                let certHash = sha256(data: serverCertificateData as Data)

                if certHash == certificate.hash {
                    return (.useCredential, URLCredential(trust: serverTrust))
                }

            case .byPublicKey:
                let keyHash = SecCertificateCopyKey(serverCertificate)
                    .flatMap { SecKeyCopyExternalRepresentation($0, nil) }
                    .map { sha256(data: $0 as Data) }

                if keyHash == certificate.hash {
                    return (.useCredential, URLCredential(trust: serverTrust))
                }
            }
        }

        return (.cancelAuthenticationChallenge, nil)
    }
}
