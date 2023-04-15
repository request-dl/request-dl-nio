/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

/**
 The Session object is used to set various properties related to the request context.

 By using this object, we can centralize the creation of a single type of session to be used
 in all requests. For example:

 ```swift
 struct MyAppConfiguration: Property {

     var body: some Property {
         Session()
             .waitsForConnectivity(true)

         Timeout(10)
     }
 }
 ```
 */
public struct Session: Property {

    private var _configuration: Internals.Session.Configuration
    var dnsOverride: [String: String]
    let provider: SessionProvider

    var configuration: Internals.Session.Configuration {
        var configuration = _configuration
        configuration.setValue(dnsOverride, forKey: \.dnsOverride)
        return configuration
    }

    fileprivate init(
        configuration: Internals.Session.Configuration,
        provider: SessionProvider
    ) {
        self._configuration = configuration
        self.dnsOverride = [:]
        self.provider = provider
    }

    /// Initializes a new Session object.
    public init() {
        self.init(
            configuration: .init(),
            provider: .shared
        )
    }

    /**
     Initializes a new Session object with a custom identifier and number of threads.

     - Parameters:
        - identifier: A custom identifier for the session.
        - numberOfThreads: The number of threads to use for the session. Defaults to 1.
     */
    public init(
        _ identifier: String,
        numberOfThreads: Int = 1
    ) {
        self.init(
            configuration: .init(),
            provider: .identified(identifier, numberOfThreads: numberOfThreads)
        )
    }

    public init(_ customLoopGroup: NIOCore.EventLoopGroup) {
        self.init(
            configuration: .init(),
            provider: .custom(customLoopGroup)
        )
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

private extension Session {

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }

    func editConfiguration(_ edit: (inout Internals.Session.Configuration) -> Void) -> Self {
        self.edit { edit(&$0._configuration) }
    }
}

extension Session {

    /**
     Set whether the session should wait for connectivity before making a request.

     - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
     - Returns: The modified `Session` instance with the waiting for connectivity flag configured.
     */
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        editConfiguration { $0.setValue(flag, forKey: \.networkFrameworkWaitForConnectivity) }
    }

    /**
     Configures the maximum number of connections per host for the session.

     - Parameter maximum: The maximum number of connections per host.
     - Returns: The modified `Session` instance with the maximum connections per host configured.
     */
    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        editConfiguration { $0.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximum }
    }

    /**
     Disables redirect for the session.

     - Returns: The modified `Session` instance with redirect disabled.
     */
    public func disableRedirect() -> Self {
        editConfiguration { $0.redirectConfiguration = .disallow }
    }

    /**
     Enables redirect follow for the session.

     - Parameters:
        - max: The maximum number of redirects to follow.
        - allowCycles: Whether to allow redirect cycles or not.
     - Returns: The modified `Session` instance with redirect follow enabled.
     */
    public func enableRedirectFollow(max: Int, allowCycles: Bool) -> Self {
        editConfiguration { $0.redirectConfiguration = .follow(max: max, allowCycles: allowCycles) }
    }

    /**
     Ignores unclean SSL shutdown for the session.

     - Returns: The modified `Session` instance with unclean SSL shutdown ignored.
     */
    public func ignoreUncleanSSLShutdown() -> Self {
        editConfiguration { $0.ignoreUncleanSSLShutdown = true }
    }

    /**
     Disables decompression for the session.

     - Returns: The modified `Session` instance with decompression disabled.
     */
    public func disableDecompression() -> Self {
        editConfiguration { $0.decompression = .disabled }
    }

    /**
     Configures the decompression limit for the session.

     - Parameter decompressionLimit: The decompression limit to set.
     - Returns: The modified `Session` instance with the decompression limit configured.
     */
    public func decompressionLimit(_ decompressionLimit: DecompressionLimit) -> Self {
        editConfiguration { $0.decompression = .enabled(limit: decompressionLimit.build()) }
    }

    /**
     Overrides DNS settings for a specific destination with a custom origin.

     - Parameters:
        - destination: The destination for which DNS settings are to be overridden.
        - origin: The custom origin to use for DNS resolution.
     - Returns: The modified `Session` instance with the DNS override configured.
     */
    public func overrideDNS(_ destination: String, from origin: String) -> Self {
        edit { $0.dnsOverride[origin] = destination }
    }
}

extension Session {

    struct Node: PropertyNode {

        let configuration: Internals.Session.Configuration
        let provider: SessionProvider

        func make(_ make: inout Make) async throws {}
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Session>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Node(
            configuration: property.configuration,
            provider: property.provider
        )))
    }
}
