/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum FatalError {

        typealias Closure = @Sendable (String, StaticString, UInt) -> Never

        fileprivate final class State: @unchecked Sendable {

            var closure: Closure {
                get { lock.withLock { _closure } }
                set { lock.withLock { _closure = newValue } }
            }

            private let lock = Lock()
            private var _closure: Closure = defaultClosure

            init() {}
        }

        fileprivate static let state = State()

        private static let defaultClosure: Closure = {
            Swift.fatalError($0, file: $1, line: $2)
        }

        static func replace(with closure: @escaping Closure) {
            self.state.closure = closure
        }

        static func restore() {
            state.closure = defaultClosure
        }
    }
    #endif

    static func fatalError(
        _ message: @Sendable @autoclosure () -> String = String(),
        file: StaticString = #file,
        line: UInt = #line
    ) -> Never {
        #if DEBUG
        FatalError.state.closure(message(), file, line)
        #else
        Swift.fatalError(
            message(),
            file: file,
            line: line
        )
        #endif
    }
}
