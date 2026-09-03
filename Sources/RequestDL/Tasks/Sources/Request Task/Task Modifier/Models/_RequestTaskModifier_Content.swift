//
// See LICENSE for this package's licensing information.
//

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _RequestTaskModifier_Content<Modifier: RequestTaskModifier>: RequestTask {

    // MARK: - Internal properties

    let task: any RequestTask<Modifier.Input>
    let environment: RequestEnvironmentValues

    // MARK: - Inits

    init<Content: RequestTask>(
        _ task: Content,
        environment: RequestEnvironmentValues = .init()
    ) where Content.Element == Modifier.Input {
        self.task = task
        self.environment = environment
    }

    // MARK: - Public methods

    // `result()` uses the environment fixed in at construction (by `ModifiedRequestTask` --
    // either empty, for a plain top-of-chain `.result()`, or scoped by
    // `ModifiedRequestTask._result(environment:)` to whatever an outer modifier passed down).
    // `_result(environment:)` must NOT delegate to `result()` (the protocol's default does that,
    // ignoring its own argument): `Modifiers.Environment.body` calls this directly with a
    // *mutated* environment that deliberately differs from `self.environment` -- that mutation is
    // the entire mechanism by which `.environment()` takes effect.
    public func result() async throws -> Modifier.Input {
        try await task._result(environment: environment)
    }

    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> Modifier.Input {
        try await task._result(environment: environment)
    }
}
