/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

final class SessionTask: @unchecked Sendable {

    // MARK: - Internal properties

    let response: Internals.AsyncResponse

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _eventLoopFuture: EventLoopFuture<Void>?

    // MARK: - Inits

    init(_ response: Internals.AsyncResponse) {
        self.response = response
    }

    // MARK: - Internal methods

    func attach(_ eventLoopFuture: EventLoopFuture<Void>) {
        lock.withLockVoid {
            self._eventLoopFuture = eventLoopFuture
        }
    }
}
