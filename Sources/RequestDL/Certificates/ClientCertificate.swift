import Foundation

public struct ClientCertificate: Request {

    private let data: Data
    private let password: String

    public init(_ data: Data, password: String) {
        self.data = data
        self.password = password
    }

    public init(name: String, in bundle: Bundle, password: String) {
        guard
            let path = bundle.path(forResource: name, ofType: "pfx"),
            let data = FileManager.default.contents(atPath: path)
        else { fatalError() }

        self.init(data, password: password)
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension ClientCertificate: PrimitiveRequest {

    struct Object: NodeObject {

        private let data: Data
        private let password: String

        init(_ data: Data, password: String) {
            self.data = data
            self.password = password
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            delegate.onDidReceiveChallenge {
                receivedChallenge($0)
            }
        }
    }

    func makeObject() -> Object {
        Object(data, password: password)
    }
}

private extension ClientCertificate.Object {

    func receivedChallenge(_ challenge: URLAuthenticationChallenge) -> DelegateProxy.ChallengeCredential {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            return (.rejectProtectionSpace, nil)
        }

        guard
            let thePKCS12 = PKCS12(data, password: password),
            let credentials = URLCredential(PKCS12: thePKCS12)
        else {
            fatalError("SecPKCS12Import returned an error trying to import PKCS12 data")
        }

        return (.useCredential, credentials)
    }
}

extension URLCredential {

    public convenience init?(PKCS12 thePKCS12: PKCS12) {
        guard let identity = thePKCS12.identity else {
            return nil
        }

        self.init(
            identity: identity,
            certificates: thePKCS12.certChain,
            persistence: .forSession
        )
    }
}
