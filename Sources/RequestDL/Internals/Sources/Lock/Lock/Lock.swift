/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct Lock: Sendable {

    private let lock = NIOLock()

    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        try lock.withLock(body)
    }

    func withLockVoid(
        _ body: () throws -> Void
    ) rethrows {
        try lock.withLockVoid(body)
    }
}
