//
// See LICENSE for this package's licensing information.
//

/// Conformed by ``DataTask``, ``DownloadTask``, and ``UploadTask`` -- the concrete task types
/// that can resolve their own ``TaskDescriptorContext`` and hand it to a ``TaskDescriptor``.
/// ``DescribingRequestTask`` is generic over this instead of `RequestTask` directly because
/// `description(_:)` isn't a `RequestTask` requirement -- an arbitrary custom conformance has no
/// way to produce a `TaskDescriptorContext` from itself.
protocol DescribableRequestTask: RequestTask {

    func description<Descriptor: TaskDescriptor>(_ descriptor: Descriptor) async throws -> Descriptor.Output
}

/// Backs the `description(_:enabled:onDescribe:)` overload -- unlike plain ``description(_:)``,
/// which runs immediately, this defers both passes until the wrapping ``AnyTask`` is actually
/// executed via `result()`/`_result(environment:)`, the same way a ``RequestTaskModifier``
/// defers its own `body(_:)` until then.
struct DescribingRequestTask<Task: DescribableRequestTask, Descriptor: TaskDescriptor>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let descriptor: Descriptor
    let enabled: Bool
    let onDescribe: @Sendable (Descriptor.Output) -> Void

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        if enabled {
            onDescribe(try await task.description(descriptor))
        }

        return try await task._result(environment: environment)
    }
}
