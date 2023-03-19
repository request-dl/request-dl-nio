/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Security
import CommonCrypto

/**
 A representation of the server trust, that contains one or more certificates that the server uses
 to identify itself to the client.

 Use the `ServerTrust` structure to configure the server trust policy of a URL session. The
 server trust policy determines how to validate the server's TLS certificate chain.

 You can initialize a `ServerTrust` instance with one or more `Certificate` instances
 that identify the trusted certificates of the server.

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
        bodyException()
    }
}

extension ServerTrust: PrimitiveProperty {

    struct Object: NodeObject {

        private let certificates: [Certificate]

        public init(_ certificates: [Certificate]) {
            self.certificates = certificates
        }

        func makeProperty(_ make: Make) {
            make.delegate.onDidReceiveChallenge {
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

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.rejectProtectionSpace, nil)
        }

        let serverCertificates = serverTrust.certificates.compactMap(\.data)

        for certificate in certificates {
            guard
                let url = certificate.bundle.resolveURL(forResourceName: certificate.name),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { continue }

            if serverCertificates.contains(data) {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        }

        return (.cancelAuthenticationChallenge, nil)
    }
}
