import Foundation

/// Executes an asynchronous operation with a timeout.
/// If the operation doesn't complete within the specified time, it will be cancelled.
/// - Parameters:
///   - seconds: The timeout duration in seconds.
///   - valueType: The type of value to return (inferred automatically).
///   - body: The asynchronous operation to execute.
/// - Returns: The result of the operation if it completes within the timeout.
/// - Throws: CancellationError if the timeout is reached, or any error thrown by the operation.
@discardableResult
public func withTaskTimeout<Value: Sendable>(
    seconds: TimeInterval,
    of valueType: Value.Type = Value.self,
    body: @Sendable @escaping () async throws -> Value
) async throws -> Value {
    let result = try await withUnsafeThrowingContinuation { continuation in
        let task = Task {
            do {
                let value = try await body()
                try Task.checkCancellation()
                continuation.resume(returning: value)
            } catch is CancellationError {} catch {
                continuation.resume(throwing: error)
            }
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                task.cancel()
                continuation.resume(throwing: CancellationError())
            } catch {}
        }

        Task {
            _ = await task.value
            timeoutTask.cancel()
        }
    }

    return result
}
