//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct Resolved: Sendable {
    let session: Internals.Session
    let requestConfiguration: RequestConfiguration
    let dataCache: DataCache
}
