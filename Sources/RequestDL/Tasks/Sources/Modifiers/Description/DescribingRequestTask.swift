//
// See LICENSE for this package's licensing information.
//

/// Backs `description(_:enabled:onDescribe:)`. Queues a hook on the environment instead of
/// producing a ``TaskDescriptorContext`` itself -- there's no generic way to do that from an
/// arbitrary `RequestTask` (only `RawTask`, sitting under whatever chain of modifiers wraps it,
/// actually resolves a `Property` tree). `RawTask._result(environment:)` is what runs the queued
/// hooks, with the exact configuration it's about to send for real.
struct DescribingRequestTask<Task: RequestTask, Descriptor: TaskDescriptor>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let descriptor: Descriptor
    let enabled: Bool
    let onDescribe: @Sendable (Descriptor.Output) -> Void

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        guard enabled else {
            return try await task._result(environment: environment)
        }

        var environment = environment

        // Only fills in a box no outer `.description(_:enabled:onDescribe:)` already queued one
        // for -- `FormNode` deposits into whichever box was current when it ran, so a shared box
        // is what lets nested calls each still see every form field, not just the ones declared
        // after the innermost one set up its own.
        if environment.descriptorFormFields == nil {
            environment.descriptorFormFields = DescriptorFormFieldBox()
        }

        environment.taskDescriptorContextHooks.append { context in
            onDescribe(try await descriptor.describe(context))
        }

        return try await task._result(environment: environment)
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Returns a task that, once performed, resolves this request through `descriptor`, hands
    /// the output to `onDescribe`, then performs the request for real -- both from the one
    /// resolve pass the request already needs, not two separate ones. Nothing runs until the
    /// returned task is: it composes lazily, the same way ``modifier(_:)`` does.
    ///
    /// Works anywhere in a task chain -- directly on ``DataTask``/``DownloadTask``/``UploadTask``,
    /// or after any modifier (`.extractPayload()`, `.map(_:)`, ...) -- since it queues its hook on
    /// the environment rather than depending on the task in front of it exposing anything special.
    /// A task with no `Property` tree to resolve (a mock, for instance) simply never triggers the
    /// hook; `onDescribe` is skipped rather than the call failing to compile or throwing.
    ///
    /// - Parameters:
    ///   - descriptor: The ``TaskDescriptor`` that produces the description.
    ///   - enabled: When `false`, skips queuing the hook entirely (`onDescribe` is not called)
    ///   and performs the request exactly as ``result()`` would -- useful to disable the pass in
    ///   production without removing the call site.
    ///   - onDescribe: Called with the descriptor's output once it's ready.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func description<Descriptor: TaskDescriptor>(
        _ descriptor: Descriptor,
        enabled: Bool = true,
        onDescribe: @escaping @Sendable (Descriptor.Output) -> Void
    ) -> AnyTask<Element> {
        DescribingRequestTask(
            task: self,
            descriptor: descriptor,
            enabled: enabled,
            onDescribe: onDescribe
        )
        .eraseToAnyTask()
    }
}
