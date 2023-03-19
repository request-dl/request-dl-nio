/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
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

    public typealias Body = Never

    private var configuration: RequestDLInternals.Session.Configuration
    private let provider: RequestDLInternals.Session.Provider

    fileprivate init(
        configuration: RequestDLInternals.Session.Configuration,
        provider: RequestDLInternals.Session.Provider
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

    func edit(_ edit: (inout RequestDLInternals.Session.Configuration) -> Void) -> Self {
        var mutableConfiguration = configuration
        edit(&mutableConfiguration)
        return self
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

    public enum Configuration {

        case `default`

        case identifier(String, numberOfThreads: Int = ProcessInfo.processInfo.activeProcessorCount)

        case custom(EventLoopGroup)
    }
}

extension Session.Configuration {

    func build() -> RequestDLInternals.Session.Provider {
        switch self {
        case .default:
            return .shared
        case .identifier(let string, let numberOfThreads):
            return .identifier(string, numberOfThreads: numberOfThreads)
        case .custom(let eventLoopGroup):
            return .custom(eventLoopGroup)
        }
    }
}

extension Session {

    public enum DecompressionLimit {
        case none
        case ratio(Int)
        case size(Int)
    }
}

extension Session.DecompressionLimit {

    func build() -> RequestDLInternals.Session.Decompression.Limit {
        switch self {
        case .none:
            return .none
        case .ratio(let value):
            return .ratio(value)
        case .size(let value):
            return .size(value)
        }
    }
}

extension Session: PrimitiveProperty {

    struct Object: NodeObject {

        let configuration: RequestDLInternals.Session.Configuration
        let provider: RequestDLInternals.Session.Provider

        init(
            _ configuration: RequestDLInternals.Session.Configuration,
            _ provider: RequestDLInternals.Session.Provider
        ) {
            self.configuration = configuration
            self.provider = provider
        }

        func makeProperty(_ make: Make) {}
    }

    func makeObject() -> Object {
        .init(configuration, provider)
    }
}
