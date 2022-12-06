//
//  Session.swift
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
 Use the Session to set a series of properties related to the
 URLSessionConfiguration

 The interesting thing about using this object is that it centralizes
 its creation to define a single type of session to be used in all calls.
 Like for example:

 ```swift
 import RequestDL

 struct MyAppConfiguration: Request {

     var body: some Request {
         Session(.default)
             .cellularAccessDisabled(true)
             .waitsForConnectivity(true)
             .networkService(.video)

         Timeout(10)
     }
 }
 ```
 */
public struct Session: Request {

    public typealias Body = Never

    private var configuration: URLSessionConfiguration
    private let queue: OperationQueue?

    /// Specifies a session with the default configuration type
    /// - Parameter configuration: what kind of session configuration
    public init(_ configuration: Configuration) {
        self.configuration = configuration.sessionConfiguration
        self.queue = nil
    }

    /// Specifies the type of session and the queue that will execute the requests
    /// - Parameters:
    ///   - configuration: what kind of session configuration
    ///   - queue: the execution queue
    public init(_ configuration: Configuration, queue: OperationQueue) {
        self.configuration = configuration.sessionConfiguration
        self.queue = queue
    }

    public var body: Never {
        Never.bodyException()
    }
}

private extension Session {

    func edit(_ edit: (URLSessionConfiguration) -> Void) -> Self {
        edit(configuration)
        return self
    }
}

extension Session {

    public func networkService(_ type: URLRequest.NetworkServiceType) -> Self {
        edit { $0.networkServiceType = type }
    }

    /// default false
    public func cellularAccessDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsCellularAccess = !isDisabled }
    }

    /// default true
    public func expensiveNetworkDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsExpensiveNetworkAccess = !isDisabled }
    }

    /// default true
    public func constrainedNetworkDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsConstrainedNetworkAccess = !isDisabled }
    }

    @available(iOS 16, macOS 13, watchOS 9, tvOS 16, *)
    public func validatesDNSSec(_ flag: Bool) -> Self {
        edit { $0.requiresDNSSECValidation = flag }
    }

    /// default false
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.waitsForConnectivity = flag }
    }

    /// default false
    public func discretionary(_ flag: Bool) -> Self {
        edit { $0.isDiscretionary = flag }
    }

    public func sharedContainerIdentifier(_ identifier: String?) -> Self {
        edit { $0.sharedContainerIdentifier = identifier }
    }

    /// default true
    public func sendsLaunchEvents(_ flag: Bool) -> Self {
        edit { $0.sessionSendsLaunchEvents = flag }
    }

    public func connectionProxyDictionary(_ dictionary: [AnyHashable: Any]?) -> Self {
        edit { $0.connectionProxyDictionary = dictionary }
    }

    public func tlsProtocolSupported(minimum: tls_protocol_version_t) -> Self {
        edit { $0.tlsMinimumSupportedProtocolVersion = minimum }
    }

    public func tlsProtocolSupported(maximum: tls_protocol_version_t) -> Self {
        edit { $0.tlsMaximumSupportedProtocolVersion = maximum }
    }

    public func tlsProtocolSupported(
        minimum: tls_protocol_version_t,
        maximum: tls_protocol_version_t
    ) -> Self {
        tlsProtocolSupported(minimum: minimum)
            .tlsProtocolSupported(maximum: maximum)
    }

    /// default true
    public func pipeliningDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.httpShouldUsePipelining = !isDisabled }
    }

    /// default false
    public func setCookiesDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.httpShouldSetCookies = !isDisabled }
    }

    public func cookieAcceptPolicy(_ policy: HTTPCookie.AcceptPolicy) -> Self {
        edit { $0.httpCookieAcceptPolicy = policy }
    }

    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        edit { $0.httpMaximumConnectionsPerHost = maximum }
    }

    public func cookieStorage(_ storage: HTTPCookieStorage?) -> Self {
        edit { $0.httpCookieStorage = storage }
    }

    public func credentialStorage(_ storage: URLCredentialStorage?) -> Self {
        edit { $0.urlCredentialStorage = storage }
    }

    /// default true
    public func extendedBackgroundIdleModeDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.shouldUseExtendedBackgroundIdleMode = !isDisabled }
    }
}

extension Session {

    public enum Configuration {

        case `default`
        case ephemeral

        /// [BETA]: Report in case of errors
        case background(String)
    }
}

extension Session.Configuration {

    var sessionConfiguration: URLSessionConfiguration {
        switch self {
        case .default:
            return .default
        case .ephemeral:
            return .ephemeral
        case .background(let identifier):
            return .background(withIdentifier: identifier)
        }
    }
}

extension Session: PrimitiveRequest {

    struct Object: NodeObject {

        let configuration: URLSessionConfiguration
        let queue: OperationQueue?

        init(_ configuration: URLSessionConfiguration, _ queue: OperationQueue?) {
            self.configuration = configuration
            self.queue = queue
        }

        func makeRequest(_ configuration: RequestConfiguration) {}
    }

    func makeObject() -> Object {
        .init(configuration, queue)
    }
}
