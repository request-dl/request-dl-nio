/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

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

    var configuration: Internals.Session.Configuration
    let provider: Internals.Session.Provider

    fileprivate init(
        configuration: Internals.Session.Configuration,
        provider: Internals.Session.Provider
    ) {
        self.configuration = configuration
        self.provider = provider
    }

    public init() {
        self.init(
            configuration: .init(),
            provider: .shared
        )
    }

    public init(
        _ identifier: String,
        numberOfThreads: Int = 1
    ) {
        self.init(
            configuration: .init(),
            provider: .identifier(identifier, numberOfThreads: numberOfThreads)
        )
    }

    public init(_ customLoopGroup: EventLoopGroup) {
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

    func edit(_ edit: (inout Internals.Session.Configuration) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf.configuration)
        return mutableSelf
    }
}

extension Session {

    /**
     Set whether the session should wait for connectivity before making a request.
     - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
     - Returns: `Self` for chaining.
     */
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.setValue(flag, forKey: \.networkFrameworkWaitForConnectivity) }
    }

    /**
     Configures the maximum number of connections per host for the session.

     - Parameter maximum: The maximum number of connections per host.
     - Returns: The session instance with the configured maximum connections per host.
     */
    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        edit { $0.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximum }
    }

    public func disableRedirect() -> Self {
        edit { $0.redirectConfiguration = .disallow }
    }

    public func enableRedirectFollow(max: Int, allowCycles: Bool) -> Self {
        edit { $0.redirectConfiguration = .follow(max: max, allowCycles: allowCycles) }
    }

    public func ignoreUncleanSSLShutdown() -> Self {
        edit { $0.ignoreUncleanSSLShutdown = true }
    }

    public func disableDecompression() -> Self {
        edit { $0.decompression = .disabled }
    }

    public func decompressionLimit(_ decompressionLimit: DecompressionLimit) -> Self {
        edit { $0.decompression = .enabled(limit: decompressionLimit.build()) }
    }
}

extension Session {

    struct Node: PropertyNode {

        let configuration: Internals.Session.Configuration
        let provider: Internals.Session.Provider

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
