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
 The Session object is used to set various properties related to URLSessionConfiguration.

 By using this object, we can centralize the creation of a single type of session to be used
 in all requests. For example:

 ```swift
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

 The Session object can be initialized with a Configuration object to specify the type of
 session configuration to use. Additionally, an optional OperationQueue can be passed in
 to specify the queue that will execute the requests.

 - Note: If the queue parameter is not specified, the requests will be executed on the
 main operation queue.
 */
public struct Session: Request {

    public typealias Body = Never

    private var configuration: URLSessionConfiguration
    private let queue: OperationQueue?

    /**
     Initializes a session with the specified configuration.

     - Parameter configuration: The type of session configuration to use.
     */
    public init(_ configuration: Configuration) {
        self.configuration = configuration.sessionConfiguration
        self.queue = nil
    }

    /**
     Initializes a session with the specified configuration and operation queue.

     - Parameters:
        - configuration: The type of session configuration to use.
        - queue: The operation queue that will execute the requests.
    */
    public init(_ configuration: Configuration, queue: OperationQueue) {
        self.configuration = configuration.sessionConfiguration
        self.queue = queue
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
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

    /**
     Set the `networkServiceType` of the `URLSessionConfiguration`.
     - Parameter type: The network service type.
     - Returns: `Self` for chaining.
     */
    public func networkService(_ type: URLRequest.NetworkServiceType) -> Self {
        edit { $0.networkServiceType = type }
    }

    /**
     Disable or enable cellular access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    public func cellularAccessDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsCellularAccess = !isDisabled }
    }

    /**
     Disable or enable expensive network access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    public func expensiveNetworkDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsExpensiveNetworkAccess = !isDisabled }
    }

    /**
     Disable or enable constrained network access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    public func constrainedNetworkDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.allowsConstrainedNetworkAccess = !isDisabled }
    }

    #if swift(>=5.7.2)
    /**
     Set whether DNSSEC validation is required for the `URLSessionConfiguration`.
     - Parameter flag: `true` to require DNSSEC validation or `false` to not require it.
     - Returns: `Self` for chaining.
     */
    @available(iOS 16, macOS 13, watchOS 9, tvOS 16, *)
    public func validatesDNSSec(_ flag: Bool) -> Self {
        edit { $0.requiresDNSSECValidation = flag }
    }
    #endif

    /**
     Set whether the session should wait for connectivity before making a request.
     - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
     - Returns: `Self` for chaining.
     */
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.waitsForConnectivity = flag }
    }

    /**
     Set whether the session is discretionary.
     - Parameter flag: `true` to make the session discretionary or `false` to make it not discretionary.
     - Returns: `Self` for chaining.
     */
    public func discretionary(_ flag: Bool) -> Self {
        edit { $0.isDiscretionary = flag }
    }

    /**
     Set the shared container identifier of the `URLSessionConfiguration`.
     - Parameter identifier: The shared container identifier.
     - Returns: `Self` for chaining.
     */
    public func sharedContainerIdentifier(_ identifier: String?) -> Self {
        edit { $0.sharedContainerIdentifier = identifier }
    }

    /**
     Set whether the session sends launch events.
     - Parameter flag: `true` to send launch events or `false` to not send them.
     - Returns: `Self` for chaining.
     */
    public func sendsLaunchEvents(_ flag: Bool) -> Self {
        edit { $0.sessionSendsLaunchEvents = flag }
    }
    /**
     Set the connection proxy dictionary of the `URLSessionConfiguration`.
     - Parameter dictionary: The connection proxy dictionary.
     - Returns: `Self` for chaining.
     */
    public func connectionProxyDictionary(_ dictionary: [AnyHashable: Any]?) -> Self {
        edit { $0.connectionProxyDictionary = dictionary }
    }

    /**
     Configures the minimum supported TLS protocol version for the session.

     - Parameter minimum: The minimum supported TLS protocol version.
     - Returns: The session instance with the configured minimum TLS protocol version.
     */
    public func tlsProtocolSupported(minimum: tls_protocol_version_t) -> Self {
        edit { $0.tlsMinimumSupportedProtocolVersion = minimum }
    }

    /**
     Configures the maximum supported TLS protocol version for the session.

     - Parameter maximum: The maximum supported TLS protocol version.
     - Returns: The session instance with the configured maximum TLS protocol version.
     */
    public func tlsProtocolSupported(maximum: tls_protocol_version_t) -> Self {
        edit { $0.tlsMaximumSupportedProtocolVersion = maximum }
    }

    /**
     Configures the supported TLS protocol version range for the session.

     - Parameters:
     - minimum: The minimum supported TLS protocol version.
     - maximum: The maximum supported TLS protocol version.
     - Returns: The session instance with the configured TLS protocol version range.
     */
    public func tlsProtocolSupported(
        minimum: tls_protocol_version_t,
        maximum: tls_protocol_version_t
    ) -> Self {
        tlsProtocolSupported(minimum: minimum)
            .tlsProtocolSupported(maximum: maximum)
    }

    /**
     Disables or enables HTTP pipelining for the session.

     - Parameter isDisabled: If `true`, disables pipelining. If `false`, enables pipelining.
     - Returns: The session instance with pipelining enabled or disabled.
     */
    public func pipeliningDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.httpShouldUsePipelining = !isDisabled }
    }

    /**
     Disables or enables setting cookies for the session.

     - Parameter isDisabled: If `true`, disables cookie setting. If `false`, enables cookie setting.
     - Returns: The session instance with cookie setting enabled or disabled.
     */
    public func setCookiesDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.httpShouldSetCookies = !isDisabled }
    }

    /**
     Configures the cookie accept policy for the session.

     - Parameter policy: The cookie accept policy to use.
     - Returns: The session instance with the configured cookie accept policy.
     */
    public func cookieAcceptPolicy(_ policy: HTTPCookie.AcceptPolicy) -> Self {
        edit { $0.httpCookieAcceptPolicy = policy }
    }

    /**
     Configures the maximum number of connections per host for the session.

     - Parameter maximum: The maximum number of connections per host.
     - Returns: The session instance with the configured maximum connections per host.
     */
    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        edit { $0.httpMaximumConnectionsPerHost = maximum }
    }

    /**
     Configures the cookie storage for the session.

     - Parameter storage: The cookie storage to use.
     - Returns: The session instance with the configured cookie storage.
     */
    public func cookieStorage(_ storage: HTTPCookieStorage?) -> Self {
        edit { $0.httpCookieStorage = storage }
    }

    /**
     Configures the URL credential storage for the session.

     - Parameter storage: The URL credential storage to use.
     - Returns: The session instance with the configured URL credential storage.
     */
    public func credentialStorage(_ storage: URLCredentialStorage?) -> Self {
        edit { $0.urlCredentialStorage = storage }
    }

    /**
     Sets whether the session should use extended background idle mode.

     By default, this function sets the value of `shouldUseExtendedBackgroundIdleMode`
     to the opposite of the `isDisabled` parameter.

     - Parameter isDisabled: A boolean value that indicates whether the session should
     use extended background idle mode.

     - Returns: A reference to the current session instance.
     */
    public func extendedBackgroundIdleModeDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.shouldUseExtendedBackgroundIdleMode = !isDisabled }
    }
}

extension Session {

    /**
     A type that represents a configuration for a URLSession instance.
     */
    public enum Configuration {

        /// The default configuration for a URLSession.
        case `default`

        /// A configuration for a URLSession that uses a private browsing session
        /// that doesn’t persist the data longer than the process lifetime.
        case ephemeral

        /**
         A configuration for a URLSession that allows the application to perform
         background downloads and uploads while the app is not running.

         This configuration requires a unique identifier string that identifies the session
         and allows the system to resume the session if necessary.

         **This case is in beta and may change in future releases.**

         - Parameter identifier: A unique identifier string that identifies the session.
         */
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
