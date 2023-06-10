/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Represents the Cache Header property that can be set in a URLRequest.

 Usage:

 ```swift
 CacheHeader()
     .maxAge(60)
     .cached(true)
     .stored(true)
 ```
 */
public struct CacheHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    var isCached = true

    var isStored = true

    var isTransformed = true

    var isOnlyIfCached = false

    var isPublic: Bool?

    var maxAge: Int?

    var sharedMaxAge: Int?

    var maxStale: Int?

    var staleWhileRevalidate: Int?

    var staleIfError: Int?

    var needsRevalidate = false

    var needsProxyRevalidate = false

    var isImmutable = false

    // MARK: - Inits

    /**
     Initializes a Cache object with default values.
     */
    public init() {}

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<CacheHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let value = property.pointer()
            .makeContents()
            .joined(separator: ", ")

        if value.isEmpty {
            return .empty
        }

        return .leaf(HeaderNode(
            key: "Cache-Control",
            value: value,
            strategy: inputs.environment.headerStrategy
        ))
    }

    // MARK: - Public methods

    /**
     Sets the "no-cache" flag to the given value.

     - Parameters:
     - flag: The value to be set.
     - Returns: The modified Cache object.
     */
    public func cached(_ flag: Bool) -> Self {
        edit { $0.isCached = flag }
    }

    /**
     Sets the "no-store" flag to the given value.

     - Parameters:
     - flag: The value to be set.
     - Returns: The modified Cache object.
     */
    public func stored(_ flag: Bool) -> Self {
        edit { $0.isStored = flag }
    }

    /**
     Sets the "no-transform" flag to the given value.

     - Parameters:
     - flag: The value to be set.
     - Returns: The modified Cache object.
     */
    public func transformed(_ flag: Bool) -> Self {
        edit { $0.isTransformed = flag }
    }

    /**
     Sets the "only-if-cached" flag to the given value.

     - Parameters:
     - flag: The value to be set.
     - Returns: The modified Cache object.
     */
    public func onlyIfCached(_ flag: Bool) -> Self {
        edit { $0.isOnlyIfCached = flag }
    }

    /**
     Sets the "public" flag to the given value.

     - Parameters:
     - flag: The value to be set.
     - Returns: The modified Cache object.
     */
    public func `public`(_ flag: Bool) -> Self {
        edit { $0.isPublic = flag }
    }

    /**
     Sets the "max-age" value to the given number of seconds.

     - Parameters:
     - seconds: The value to be set.
     - Returns: The modified Cache object.
     */
    public func maxAge(_ seconds: Int) -> Self {
        edit { $0.maxAge = seconds }
    }

    /**
     Sets the "s-maxage" value to the given number of seconds.

     - Parameters:
     - seconds: The value to be set.
     - Returns: The modified Cache object.
     */
    public func sharedMaxAge(_ seconds: Int) -> Self {
        edit { $0.sharedMaxAge = seconds }
    }

    /**
     Sets the "max-stale" value to the given number of seconds.

     - Parameters:
     - seconds: The value to be set.
     - Returns: The modified Cache object.
     */
    public func maxStale(_ seconds: Int) -> Self {
        edit { $0.maxStale = seconds }
    }

    /**
     Sets the "stale-while-revalidate" value to the given number of seconds.

     - Parameters:
     - seconds: The value to be set.
     - Returns: The modified Cache object.
     */
    public func staleWhileRevalidate(_ seconds: Int) -> Self {
        edit { $0.staleWhileRevalidate = seconds }
    }

    /**
     Sets the `stale-if-error` value to the given number of seconds.

     - Parameter seconds: The value to be set.
     - Returns: The modified Cache object.
     */
    public func staleIfError(_ seconds: Int) -> Self {
        edit { $0.staleIfError = seconds }
    }

    /**
     Sets the "must-revalidate" flag.

     - Returns: The modified Cache object.
     */
    public func mustRevalidate() -> Self {
        edit { $0.needsRevalidate = true }
    }

    /**
     Sets the "proxy-revalidate" flag.

     - Returns: The modified Cache object.
     */
    public func proxyRevalidate() -> Self {
        edit { $0.needsProxyRevalidate = true }
    }

    /**
     The `immutable()` function sets the cache's immutability flag to `true`, indicating that
     he cached response cannot be modified or updated by a server.

     - Returns: The modified Cache object.
     */
    public func immutable() -> Self {
        edit { $0.isImmutable = true }
    }

    // MARK: - Internal methods

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }

    // MARK: - Private methods

    // swiftlint:disable cyclomatic_complexity

    private func makeContents() -> [String] {
        var contents = [String]()

        if !isCached {
            contents.append("no-cache")
        }

        if !isStored {
            contents.append("no-store")
        }

        if !isTransformed {
            contents.append("no-transform")
        }

        if isOnlyIfCached {
            contents.append("only-if-cached")
        }

        if let isPublic = isPublic {
            contents.append(isPublic ? "public" : "private")
        }

        if let maxAge = maxAge {
            contents.append("max-age=\(maxAge)")
        }

        if let sharedMaxAge = sharedMaxAge {
            contents.append("s-maxage=\(sharedMaxAge)")
        }

        if let maxStale = maxStale {
            contents.append("max-stale\(maxStale > .zero ? "=\(maxStale)" : "")")
        }

        if let staleWhileRevalidate = staleWhileRevalidate {
            contents.append("stale-while-revalidate=\(staleWhileRevalidate)")
        }

        if let staleIfError = staleIfError {
            contents.append("stale-if-error=\(staleIfError)")
        }

        if needsRevalidate {
            contents.append("must-revalidate")
        }

        if needsProxyRevalidate {
            contents.append("proxy-revalidate")
        }

        if isImmutable {
            contents.append("immutable")
        }

        return contents
    }

    // swiftlint:enable cyclomatic_complexity
}
