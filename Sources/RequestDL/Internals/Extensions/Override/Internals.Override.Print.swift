/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum Print: Sendable {
        typealias Closure = @Sendable (String, String, Sendable...) -> Void

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
            Swift.print($2, separator: $0, terminator: $1)
        }

        static func replace(with closure: @escaping Closure) {
            self.state.closure = closure
        }

        static func restore() {
            state.closure = defaultClosure
        }
    }
    #endif

    static func print(_ items: Sendable..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Print.state.closure(separator, terminator, items)
        #else
        Swift.print(items, separator: separator, terminator: terminator)
        #endif
    }
}
