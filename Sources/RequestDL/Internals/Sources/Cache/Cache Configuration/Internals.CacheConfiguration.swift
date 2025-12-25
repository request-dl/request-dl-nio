/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

import Logging

extension Internals {

    struct CacheConfiguration: Sendable, Equatable {

        enum Directory: Sendable, Equatable {
            case url(URL)
            case custom(String)
            case main
        }

        // MARK: - Internal properties

        var memoryCapacity: UInt64?
        var diskCapacity: UInt64?
        var directory: Directory?

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func build(logger: Logger?) -> DataCache {
            let directory = directory ?? .main
            let directoryURL: URL

            switch directory {
            case .main:
                directoryURL = DataCache.mainTemporaryURL()
            case .custom(let suiteName):
                directoryURL = DataCache.temporaryURL(suiteName: suiteName)
            case .url(let url):
                directoryURL = url
            }

            let lazyDataCache = DataCache(url: directoryURL, logger: logger)

            if memoryCapacity == nil || memoryCapacity == .zero {
                lazyDataCache.memoryCapacity = max(lazyDataCache.memoryCapacity, 1_024 * 1_024 * 2)
            }

            if diskCapacity == nil || diskCapacity == .zero {
                lazyDataCache.diskCapacity = max(lazyDataCache.diskCapacity, 1_024 * 1_024 * 2)
            }

            return .init(
                memoryCapacity: memoryCapacity ?? .zero,
                diskCapacity: diskCapacity  ?? .zero,
                url: directoryURL,
                logger: logger
            )
        }
    }
}
