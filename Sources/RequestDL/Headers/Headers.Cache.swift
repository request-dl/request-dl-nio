//
//  Headers.Cache.swift
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

    struct CacheObject: NodeObject {

        private let policy: URLRequest.CachePolicy?
        private let memoryCapacity: Int?
        private let diskCapacity: Int?

        init(
            policy: URLRequest.CachePolicy?,
            memoryCapacity: Int?,
            diskCapacity: Int?
        ) {
            self.policy = policy
            self.memoryCapacity = memoryCapacity
            self.diskCapacity = diskCapacity
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            if let memoryCapacity = memoryCapacity, let diskCapacity = diskCapacity {
                configuration.configuration.urlCache = URLCache(
                    memoryCapacity: memoryCapacity,
                    diskCapacity: diskCapacity,
                    diskPath: Bundle.main.bundleIdentifier
                )
            }

            if let policy = policy {
                configuration.request.cachePolicy = policy
            }
        }
    }

    func makeObject() -> Headers.Object {
        Headers.Object(
            contents().joined(separator: ", "),
            forKey: "Cache-Control",
            next: CacheObject(
                policy: policy,
                memoryCapacity: memoryCapacity,
                diskCapacity: diskCapacity
            )
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
