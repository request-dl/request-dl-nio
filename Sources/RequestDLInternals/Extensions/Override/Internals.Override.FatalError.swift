//
// See LICENSE for this package's licensing information.
//

extension Internals.Override {

    #if DEBUG
    /// Swaps out `fatalError(_:file:line:)` for the duration of an operation.
    ///
    /// Task local, so a replacement is visible to the operation and to everything it awaits,
    /// and to nothing running in parallel beside it.
    ///
    /// - Important: The closure returns `Never`. A substitute that returns normally is not an
    /// option, so a test replacing this one throws, or traps in its own way.
    package enum FatalError {

        package typealias Closure = @Sendable (String, StaticString, UInt) -> Never

        @TaskLocal
        fileprivate static var closure: Closure = {
            Swift.fatalError($0, file: $1, line: $2)
        }

        package static func replace<T: Sendable>(
            with closure: @escaping Closure,
            perform: @Sendable () async throws -> T
        ) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }

        package static func replace<T>(with closure: @escaping Closure, perform: @Sendable () throws -> T) rethrows -> T
        {
            try $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    /// Stops the process, or hands the message to whatever a test substituted.
    package static func fatalError(
        _ message: @Sendable @autoclosure () -> String = String(),
        file: StaticString = #file,
        line: UInt = #line
    ) -> Never {
        #if DEBUG
        FatalError.closure(message(), file, line)
        #else
        Swift.fatalError(
            message(),
            file: file,
            line: line
        )
        #endif
    }
}

extension Internals {

    /// Stops the process over a bug in this package, as opposed to a misuse of it by the caller.
    package static func preconditionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never
    {
        #if DEBUG
        Internals.Override.fatalError("🐞 RequestDL bug: \(message)", file: file, line: line)
        #else
        Internals.Override.fatalError(message, file: file, line: line)
        #endif
    }
}
