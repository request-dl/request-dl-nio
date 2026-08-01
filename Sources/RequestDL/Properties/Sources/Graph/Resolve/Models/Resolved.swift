//
// See LICENSE for this package's licensing information.
//

struct Resolved: Sendable {
    let session: Internals.Session
    let requestConfiguration: RequestConfiguration
    let dataCache: DataCache
}
