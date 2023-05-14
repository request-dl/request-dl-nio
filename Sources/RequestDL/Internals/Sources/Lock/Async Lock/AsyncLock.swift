/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Semaphore

struct AsyncLock: Sendable {

    // MARK: - Private properties

    private let asyncSemaphore = AsyncSemaphore(value: 1)

    // MARK: - Internal methods

    func withLock<Value: Sendable>(
        _ body: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        await asyncSemaphore.wait()
        let value = try await body()
        asyncSemaphore.signal()
        return value
    }

    func withLockVoid(
        _ body: @Sendable () async throws -> Void
    ) async rethrows {
        await asyncSemaphore.wait()
        try await body()
        asyncSemaphore.signal()
    }

    func lock() async {
        await asyncSemaphore.wait()
    }

    func unlock() {
        asyncSemaphore.signal()
    }
}
