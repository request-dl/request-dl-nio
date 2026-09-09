//
// See LICENSE for this package's licensing information.
//

import Logging

/// Carries the `Logger` configured for the `Property` graph currently being resolved, for the
/// few precondition/assertion-failure paths reached deep inside graph construction (`bodyException()`,
/// `assertPathway()`, `Certificate.Format.resolve(for:in:)`) that have no `_PropertyInputs` in
/// scope to read it from directly.
///
/// Scoped to `Property` resolution only -- bound once per `Resolve.outputs()` call, to that
/// resolve's own `environment.logger` -- unlike the `@TaskLocal` `RequestEnvironmentValues.current`
/// used to be: a nested `Resolve` (a `RequestTask` built from within another task's `result()`)
/// rebinds this to its own logger before building its own graph, so there's nothing here for it
/// to inherit by accident.
enum PropertyResolutionLogger {

    @TaskLocal
    static var current: Logger?
}
