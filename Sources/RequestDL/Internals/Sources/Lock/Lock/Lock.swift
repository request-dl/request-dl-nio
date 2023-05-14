/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct Lock: Sendable {

    // MARK: - Private properties

    private let _lock = NIOLock()

    // MARK: - Internal methods

    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        try _lock.withLock(body)
    }

    func withLockVoid(
        _ body: () throws -> Void
    ) rethrows {
        try _lock.withLockVoid(body)
    }
}
