//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

/// Portable stand-in for `NIOConcurrencyHelpers.NIOLockedValueBox`, for tests that capture a
/// value across an escaping closure (a redirect/tracer callback, say) and read it back
/// afterward. Same `withLockedValue` call-site shape, so a test reads identically regardless of
/// which lock actually backs it.
final class LockedValueBox<Value>: @unchecked Sendable {

    private let lock = Lock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    @discardableResult
    func withLockedValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock {
            body(&_value)
        }
    }
}
