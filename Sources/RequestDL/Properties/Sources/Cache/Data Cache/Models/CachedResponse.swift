/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct CachedResponse: Sendable, Codable, Hashable {

    // MARK: - Internal properties

    let response: Internals.ResponseHead

    let policy: DataCache.Policy.Set

    let date: Date

    // MARK: - Inits

    init(
        response: Internals.ResponseHead,
        policy: DataCache.Policy.Set
    ) {
        self.response = response
        self.policy = policy
        self.date = Date()
    }
}
