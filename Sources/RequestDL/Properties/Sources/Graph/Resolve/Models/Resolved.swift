/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct Resolved {

    let session: Internals.Session
    let request: Internals.Request
}
