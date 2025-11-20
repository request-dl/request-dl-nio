/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum FatalError {

        typealias Closure = @Sendable (String, StaticString, UInt) -> Never

        @TaskLocal
        fileprivate static var closure: Closure = {
            Swift.fatalError($0, file: $1, line: $2)
        }

        static func replace<T: Sendable>(with closure: @escaping Closure, perform: @Sendable () async throws -> T) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }

        static func replace<T>(with closure: @escaping Closure, perform: @Sendable () throws -> T) rethrows -> T {
            try $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    static func fatalError(
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

    static func preconditionFailure(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never {
        #if DEBUG
        Internals.Override.fatalError("🐞 RequestDL bug: \(message)", file: file, line: line)
        #else
        Internals.Override.fatalError("RequestDL internal error", file: file, line: line)
        #endif
    }
}
