/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct Lock: Sendable {

    // MARK: - Private properties

    private let lock = NIOLock()

    // MARK: - Internal methods

    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        try lock.withLock(body)
    }

    func withLockVoid(
        _ body: () throws -> Void
    ) rethrows {
        try lock.withLockVoid(body)
    }
}
