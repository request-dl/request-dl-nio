//
// See LICENSE for this package's licensing information.
//

/// Thrown by ``eventually(timeout:_:)`` and ``completing(within:_:)`` when time runs out.
package struct EventuallyTimeoutError: Error, CustomStringConvertible {

    package let timeout: Double

    package var description: String {
        "Condition still unmet after \(timeout)s"
    }
}

/// Polls `condition` until it holds, or throws ``EventuallyTimeoutError`` after `timeout`
/// seconds.
///
/// For tests that need to wait for something they cannot await directly -- a producer reaching
/// a paused state, a background task giving up a resource -- without sleeping a fixed duration
/// and hoping, the same reason `AsyncSignal.waitForWaiters(_:timeout:)` exists.
package func eventually(
    timeout: Double = 10,
    _ condition: @Sendable () async throws -> Bool
) async throws {
    // Counted in polls rather than measured against a clock: `ContinuousClock` needs a newer
    // deployment target than this package's, and a poll that overruns only makes the wait longer,
    // never a pass into a failure.
    let polls = max(1, Int(timeout * 100))

    for _ in 0..<polls {
        if try await condition() {
            return
        }

        try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
    }

    guard try await condition() else {
        throw EventuallyTimeoutError(timeout: timeout)
    }
}

/// Runs `operation` in a task of its own and returns its result, or throws
/// ``EventuallyTimeoutError`` if it hasn't finished after `timeout` seconds.
///
/// For regression tests guarding against a hang: awaiting the operation directly would hang the
/// test (and the suite) instead of failing it. On timeout the task is cancelled and left behind;
/// there is nothing better to do with an operation that is, by assumption, stuck.
package func completing<Value: Sendable>(
    within timeout: Double = 10,
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let result = LockedValueBox<Result<Value, any Error>?>(nil)

    let task = _Concurrency.Task {
        do {
            let value = try await operation()
            result.withLockedValue { $0 = .success(value) }
        } catch {
            result.withLockedValue { $0 = .failure(error) }
        }
    }

    do {
        try await eventually(timeout: timeout) {
            result.withLockedValue { $0 != nil }
        }
    } catch {
        task.cancel()
        throw error
    }

    return try result.withLockedValue { $0! }.get()
}
