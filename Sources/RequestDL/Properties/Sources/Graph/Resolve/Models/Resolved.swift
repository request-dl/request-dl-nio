/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Resolved: Sendable {
    let session: Internals.Session
    let request: Internals.Request
}
