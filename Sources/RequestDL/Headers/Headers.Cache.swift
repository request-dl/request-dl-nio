import Foundation

extension Headers {

    public struct Cache: Request {

        private let policy: URLRequest.CachePolicy?
        private let memoryCapacity: Int?
        private let diskCapacity: Int?

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

        public init() {
            memoryCapacity = nil
            diskCapacity = nil
            policy = nil
        }

        public init(
            _ policy: URLRequest.CachePolicy,
            memoryCapacity: Int = 10_000_000,
            diskCapacity: Int = 1_000_000_000
        ) {
            self.policy = policy
            self.memoryCapacity = memoryCapacity
            self.diskCapacity = diskCapacity
        }

        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Cache: PrimitiveRequest {

    struct Object: NodeObject {

        private let policy: URLRequest.CachePolicy?
        private let memoryCapacity: Int?
        private let diskCapacity: Int?
        private let contents: [String]

        init(
            policy: URLRequest.CachePolicy?,
            memoryCapacity: Int?,
            diskCapacity: Int?,
            contents: [String]
        ) {
            self.policy = policy
            self.memoryCapacity = memoryCapacity
            self.diskCapacity = diskCapacity
            self.contents = contents
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            if !contents.isEmpty {
                request.setValue(contents.joined(separator: ", "), forHTTPHeaderField: "Cache-Control")
            }

            if let memoryCapacity = memoryCapacity, let diskCapacity = diskCapacity {
                configuration.urlCache = URLCache(
                    memoryCapacity: memoryCapacity,
                    diskCapacity: diskCapacity,
                    diskPath: Bundle.main.bundleIdentifier
                )
            }

            if let policy = policy {
                request.cachePolicy = policy
            }
        }
    }

    func makeObject() -> Object {
        .init(
            policy: policy,
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            contents: contents()
        )
    }
}

extension Headers.Cache {

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }
}

extension Headers.Cache {

    public func cached(_ flag: Bool) -> Self {
        edit { $0.isCached = flag }
    }

    public func stored(_ flag: Bool) -> Self {
        edit { $0.isStored = flag }
    }

    public func transformed(_ flag: Bool) -> Self {
        edit { $0.isTransformed = flag }
    }

    public func onlyIfCached(_ flag: Bool) -> Self {
        edit { $0.isOnlyIfCached = flag }
    }

    public func `public`(_ flag: Bool) -> Self {
        edit { $0.isPublic = flag }
    }
}

extension Headers.Cache {

    public func maxAge(_ seconds: Int) -> Self {
        edit { $0.maxAge = seconds }
    }

    public func sharedMaxAge(_ seconds: Int) -> Self {
        edit { $0.sharedMaxAge = seconds }
    }
}

extension Headers.Cache {

    public func maxStale(_ seconds: Int) -> Self {
        edit { $0.maxStale = seconds }
    }

    public func staleWhileRevalidate(_ seconds: Int) -> Self {
        edit { $0.staleWhileRevalidate = seconds }
    }

    public func staleIfError(_ seconds: Int) -> Self {
        edit { $0.staleIfError = seconds }
    }
}

extension Headers.Cache {

    public func mustRevalidate() -> Self {
        edit { $0.needsRevalidate = true }
    }

    public func proxyRevalidate() -> Self {
        edit { $0.needsProxyRevalidate = true }
    }
}

extension Headers.Cache {

    public func immutable() -> Self {
        edit { $0.isImmutable = true }
    }
}

extension Headers.Cache {

    // swiftlint:disable cyclomatic_complexity
    func contents() -> [String] {
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
}
