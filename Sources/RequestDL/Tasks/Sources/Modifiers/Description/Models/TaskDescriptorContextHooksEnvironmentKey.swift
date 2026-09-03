//
// See LICENSE for this package's licensing information.
//

private struct TaskDescriptorContextHooksRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: [@Sendable (TaskDescriptorContext) async throws -> Void] {
        []
    }
}

extension RequestEnvironmentValues {

    /// Queued by ``RequestTask/description(_:enabled:onDescribe:)`` -- never touched directly.
    ///
    /// `RawTask` is the only thing that ever reads this: right after resolving
    /// `requestConfiguration` for real (the same resolve pass a real request already needs, not
    /// an extra one), it runs every hook here with the resulting ``TaskDescriptorContext``, then
    /// carries on to actually perform the request. Reusing the one resolve pass this way is what
    /// lets `description(_:enabled:onDescribe:)` work on *any* `RequestTask` -- including one
    /// buried under `.extractPayload()`, `.map(_:)`, or any other modifier -- without every task
    /// type needing its own way to produce a ``TaskDescriptorContext``.
    var taskDescriptorContextHooks: [@Sendable (TaskDescriptorContext) async throws -> Void] {
        get { self[TaskDescriptorContextHooksRequestEnvironmentKey.self] }
        set { self[TaskDescriptorContextHooksRequestEnvironmentKey.self] = newValue }
    }
}
