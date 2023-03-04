//
//  ClientCertificate.swift
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

/**
 A representation of a client certificate that can be used in an HTTP request.

 This type conforms to the `Property` protocol, which means it can be used as a property in a
 `RequestBuilder`. It has two initializers, one that takes the certificate data and password as parameters,
 and another that takes the certificate name, bundle, and password.
 */
public struct ClientCertificate: Property {

    private let data: Data
    private let password: String

    /**
     Creates a new instance of ClientCertificate with the given certificate data and password.

     - Parameters:
        - data: The data of the certificate.
        - password: The password to access the certificate.
     */
    public init(_ data: Data, password: String) {
        self.data = data
        self.password = password
    }

    /**
     Creates a new instance of ClientCertificate with the given certificate name, bundle, and password.

     - Parameters:
        - name: The name of the certificate.
        - bundle: The bundle in which the certificate is located.
        - password: The password to access the certificate.
     */
    public init(name: String, in bundle: Bundle, password: String) {
        guard
            let url = bundle.url(forResource: name, withExtension: "pfx"),
            let data = try? Data(contentsOf: url)
        else { fatalError() }

        self.init(data, password: password)
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension ClientCertificate: PrimitiveProperty {

    struct Object: NodeObject {

        private let data: Data
        private let password: String

        init(_ data: Data, password: String) {
            self.data = data
            self.password = password
        }

        func makeProperty(_ configuration: MakeConfiguration) {
            configuration.delegate.onDidReceiveChallenge {
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

    convenience init?(PKCS12 thePKCS12: PKCS12) {
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
