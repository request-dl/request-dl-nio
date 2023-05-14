/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct CacheConfiguration: Equatable {

        enum Directory: Equatable {
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

        func build() -> DataCache {
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

            return .init(
                memoryCapacity: memoryCapacity ?? .zero,
                diskCapacity: diskCapacity  ?? .zero,
                url: directoryURL
            )
        }
    }
}
