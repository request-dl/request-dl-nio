//
// See LICENSE for this package's licensing information.
//

extension Internals.Override {

    #if DEBUG
    /// Swaps out `assertionFailure(_:file:line:)` for the duration of an operation.
    ///
    /// Task local, so a replacement is visible to the operation and to everything it awaits,
    /// and to nothing running in parallel beside it.
    package enum AssertionFailure {

        package typealias Closure = @Sendable (String, StaticString, UInt) -> Void

        @TaskLocal
        fileprivate static var closure: Closure = {
            Swift.assertionFailure($0, file: $1, line: $2)
        }

        package static func replace<T: Sendable>(
            with closure: @escaping Closure,
            perform: @Sendable () async throws -> T
        ) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }

        package static func replace<T>(with closure: @escaping Closure, perform: @Sendable () throws -> T) rethrows -> T {
            try $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    /// Reports a recoverable programming error, or hands it to whatever a test substituted.
    package static func assertionFailure(
        _ message: @Sendable @autoclosure () -> String = String(),
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #if DEBUG
        AssertionFailure.closure(message(), file, line)
        #else
        Swift.assertionFailure(
            message(),
            file: file,
            line: line
        )
        #endif
    }
}

extension Internals {

    /// Reports a bug in this package, as opposed to a misuse of it by the caller.
    ///
    /// The marker in the message is the point: it tells whoever sees it in a console that the
    /// issue belongs upstream and is worth filing.
    package static func assertionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
        #if DEBUG
        Internals.Override.assertionFailure("🐞 RequestDL bug: \(message)", file: file, line: line)
        #else
        Internals.Override.assertionFailure(message, file: file, line: line)
        #endif
    }
}
