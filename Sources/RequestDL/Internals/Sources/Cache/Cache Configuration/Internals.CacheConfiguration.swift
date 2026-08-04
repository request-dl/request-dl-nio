//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.URL
#endif

extension Internals {

    struct CacheConfiguration: Sendable, Equatable {

        enum Directory: Sendable, Equatable {
            case url(URL)
            case custom(String)
            case main
        }

        // MARK: - Internal static properties

        /// Floor applied when the caller asked for nothing, or for zero.
        private static let minimumCapacity: Int64 = 1_024 * 1_024 * 2

        // MARK: - Internal properties

        var memoryCapacity: Int64?
        var diskCapacity: Int64?
        var directory: Directory?

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        /// Builds the cache this configuration describes.
        ///
        /// - Important: Must not build one `DataCache`, raise its capacities to the floor below,
        /// then discard it and return a second one constructed with `memoryCapacity ?? .zero` —
        /// that leaves the floor as dead code, and the common path, with both capacities unset,
        /// would produce a cache with zero of each: caching off by default with nothing to say
        /// so.
        func build(logger: Logger?) -> DataCache {
            let directoryURL: URL

            switch directory ?? .main {
            case .main:
                directoryURL = DataCache.mainTemporaryURL()
            case .custom(let suiteName):
                directoryURL = DataCache.temporaryURL(suiteName: suiteName)
            case .url(let url):
                directoryURL = url
            }

            let dataCache = DataCache(url: directoryURL, logger: logger)

            dataCache.memoryCapacity = Self.resolve(memoryCapacity, default: dataCache.memoryCapacity)
            dataCache.diskCapacity = Self.resolve(diskCapacity, default: dataCache.diskCapacity)

            return dataCache
        }

        // MARK: - Private static methods

        /// A requested capacity, or the type's own default raised to the floor.
        private static func resolve(_ requested: Int64?, default defaultValue: Int64) -> Int64 {
            guard let requested, requested > .zero else {
                return max(defaultValue, minimumCapacity)
            }

            return requested
        }
    }
}
