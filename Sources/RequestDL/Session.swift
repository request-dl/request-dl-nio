/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

/**
 The Session object is used to set various properties related to URLSessionConfiguration.

 By using this object, we can centralize the creation of a single type of session to be used
 in all requests. For example:

 ```swift
 struct MyAppConfiguration: Property {

     var body: some Property {
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
public struct Session: Property {

    public typealias Body = Never

    private var configuration: HTTPClient.Configuration
    private let eventLoopGroup: HTTPClient.EventLoopGroupProvider

    fileprivate init(
        configuration: HTTPClient.Configuration,
        eventLoopGroup: HTTPClient.EventLoopGroupProvider
    ) {
        self.configuration = configuration
        self.eventLoopGroup = eventLoopGroup
    }

    /**
     Initializes a session with the specified configuration.

     - Parameter configuration: The type of session configuration to use.
     */
    public init(_ configuration: Configuration) {
        self.init(
            configuration: .init(),
            eventLoopGroup: configuration.eventLoopGroup
        )
    }

    /**
     Initializes a session with the specified configuration and operation queue.

     - Parameters:
        - configuration: The type of session configuration to use.
        - queue: The operation queue that will execute the requests.
    */
    @available(*, deprecated)
    public init(_ configuration: Configuration, queue: OperationQueue) {
        fatalError("Deprecated")
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

private extension Session {

    func edit(_ edit: (inout HTTPClient.Configuration) -> Void) -> Self {
        var mutableConfiguration = configuration
        edit(&mutableConfiguration)
        return self
    }
}

extension Session {

    /**
     Set the `networkServiceType` of the `URLSessionConfiguration`.
     - Parameter type: The network service type.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func networkService(_ type: URLRequest.NetworkServiceType) -> Self {
        fatalError("Deprecated")
    }

    /**
     Disable or enable cellular access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func cellularAccessDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
    }

    /**
     Disable or enable expensive network access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func expensiveNetworkDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
    }

    /**
     Disable or enable constrained network access for the `URLSessionConfiguration`.
     - Parameter isDisabled: `true` to disable or `false` to enable.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func constrainedNetworkDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
    }

    #if swift(>=5.7.2)
    /**
     Set whether DNSSEC validation is required for the `URLSessionConfiguration`.
     - Parameter flag: `true` to require DNSSEC validation or `false` to not require it.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    @available(iOS 16, macOS 13, watchOS 9, tvOS 16, *)
    public func validatesDNSSec(_ flag: Bool) -> Self {
        fatalError("Deprecated")
    }
    #endif

    /**
     Set whether the session should wait for connectivity before making a request.
     - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
     - Returns: `Self` for chaining.
     */
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.networkFrameworkWaitForConnectivity = flag }
    }

    /**
     Set whether the session is discretionary.
     - Parameter flag: `true` to make the session discretionary or `false` to make it not discretionary.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func discretionary(_ flag: Bool) -> Self {
        fatalError("Deprecated")
    }

    /**
     Set the shared container identifier of the `URLSessionConfiguration`.
     - Parameter identifier: The shared container identifier.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func sharedContainerIdentifier(_ identifier: String?) -> Self {
        fatalError("Deprecated")
    }

    /**
     Set whether the session sends launch events.
     - Parameter flag: `true` to send launch events or `false` to not send them.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func sendsLaunchEvents(_ flag: Bool) -> Self {
        fatalError("Deprecated")
    }
    /**
     Set the connection proxy dictionary of the `URLSessionConfiguration`.
     - Parameter dictionary: The connection proxy dictionary.
     - Returns: `Self` for chaining.
     */
    @available(*, deprecated)
    public func connectionProxyDictionary(_ dictionary: [AnyHashable: Any]?) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the minimum supported TLS protocol version for the session.

     - Parameter minimum: The minimum supported TLS protocol version.
     - Returns: The session instance with the configured minimum TLS protocol version.
     */
    @available(*, deprecated)
    public func tlsProtocolSupported(minimum: tls_protocol_version_t) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the maximum supported TLS protocol version for the session.

     - Parameter maximum: The maximum supported TLS protocol version.
     - Returns: The session instance with the configured maximum TLS protocol version.
     */
    @available(*, deprecated)
    public func tlsProtocolSupported(maximum: tls_protocol_version_t) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the supported TLS protocol version range for the session.

     - Parameters:
     - minimum: The minimum supported TLS protocol version.
     - maximum: The maximum supported TLS protocol version.
     - Returns: The session instance with the configured TLS protocol version range.
     */
    @available(*, deprecated)
    public func tlsProtocolSupported(
        minimum: tls_protocol_version_t,
        maximum: tls_protocol_version_t
    ) -> Self {
        fatalError("Deprecated")
    }

    /**
     Disables or enables HTTP pipelining for the session.

     - Parameter isDisabled: If `true`, disables pipelining. If `false`, enables pipelining.
     - Returns: The session instance with pipelining enabled or disabled.
     */
    @available(*, deprecated)
    public func pipeliningDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
    }

    /**
     Disables or enables setting cookies for the session.

     - Parameter isDisabled: If `true`, disables cookie setting. If `false`, enables cookie setting.
     - Returns: The session instance with cookie setting enabled or disabled.
     */
    @available(*, deprecated)
    public func setCookiesDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the cookie accept policy for the session.

     - Parameter policy: The cookie accept policy to use.
     - Returns: The session instance with the configured cookie accept policy.
     */
    @available(*, deprecated)
    public func cookieAcceptPolicy(_ policy: HTTPCookie.AcceptPolicy) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the maximum number of connections per host for the session.

     - Parameter maximum: The maximum number of connections per host.
     - Returns: The session instance with the configured maximum connections per host.
     */
    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        edit { $0.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximum }
    }

    /**
     Configures the cookie storage for the session.

     - Parameter storage: The cookie storage to use.
     - Returns: The session instance with the configured cookie storage.
     */
    @available(*, deprecated)
    public func cookieStorage(_ storage: HTTPCookieStorage?) -> Self {
        fatalError("Deprecated")
    }

    /**
     Configures the URL credential storage for the session.

     - Parameter storage: The URL credential storage to use.
     - Returns: The session instance with the configured URL credential storage.
     */
    @available(*, deprecated)
    public func credentialStorage(_ storage: URLCredentialStorage?) -> Self {
        fatalError("Deprecated")
    }

    /**
     Sets whether the session should use extended background idle mode.

     By default, this function sets the value of `shouldUseExtendedBackgroundIdleMode`
     to the opposite of the `isDisabled` parameter.

     - Parameter isDisabled: A boolean value that indicates whether the session should
     use extended background idle mode.

     - Returns: A reference to the current session instance.
     */
    @available(*, deprecated)
    public func extendedBackgroundIdleModeDisabled(_ isDisabled: Bool) -> Self {
        fatalError("Deprecated")
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
        @available(*, deprecated)
        case ephemeral

        /**
         A configuration for a URLSession that allows the application to perform
         background downloads and uploads while the app is not running.

         This configuration requires a unique identifier string that identifies the session
         and allows the system to resume the session if necessary.

         **This case is in beta and may change in future releases.**

         - Parameter identifier: A unique identifier string that identifies the session.
         */
        @available(*, deprecated)
        case background(String)

    }
}

extension Session.Configuration {

    var eventLoopGroup: HTTPClient.EventLoopGroupProvider {
        switch self {
        case .default:
            return .createNew
        default:
            fatalError("deprecated")
        }
    }
}

extension Session: PrimitiveProperty {

    struct Object: NodeObject {

        let configuration: HTTPClient.Configuration
        let eventLoopGroup: HTTPClient.EventLoopGroupProvider

        init(_ configuration: HTTPClient.Configuration, _ eventLoopGroup: HTTPClient.EventLoopGroupProvider) {
            self.configuration = configuration
            self.eventLoopGroup = eventLoopGroup
        }

        func makeProperty(_ make: Make) {}
    }

    func makeObject() -> Object {
        .init(configuration, eventLoopGroup)
    }
}
