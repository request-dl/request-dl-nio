//
// See LICENSE for this package's licensing information.
//

/// A type that represents a task that has been modified by a ``RequestTaskModifier``.
///
/// A ``ModifiedRequestTask`` is created by applying a ``RequestTask/modifier(_:)`` to a base
/// ``RequestTask``.
///
/// > Note: The `Element` associated type of the ``ModifiedRequestTask`` is determined by the `Output`
/// associated type of the ``RequestTaskModifier``.
public struct ModifiedRequestTask<Modifier: RequestTaskModifier>: RequestTask {

    public typealias Element = Modifier.Output

    // MARK: - Internal properties

    let task: Modifier.Content
    let modifier: Modifier

    // MARK: - Public properties

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> Element {
        let scoped = Modifier.Content(task.task, environment: environment)
        return try await modifier.body(scoped)
    }
}
