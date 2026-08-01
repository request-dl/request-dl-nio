//
// See LICENSE for this package's licensing information.
//

extension Internals.Override {

    #if DEBUG
    enum AssertionFailure {

        typealias Closure = @Sendable (String, StaticString, UInt) -> Void

        @TaskLocal
        fileprivate static var closure: Closure = {
            Swift.assertionFailure($0, file: $1, line: $2)
        }

        static func replace<T: Sendable>(
            with closure: @escaping Closure,
            perform: @Sendable () async throws -> T
        ) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }

        static func replace<T>(with closure: @escaping Closure, perform: @Sendable () throws -> T) rethrows -> T {
            try $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    static func assertionFailure(
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

    static func assertionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
        #if DEBUG
        Internals.Override.assertionFailure("🐞 RequestDL bug: \(message)", file: file, line: line)
        #else
        Internals.Override.assertionFailure(message, file: file, line: line)
        #endif
    }
}
