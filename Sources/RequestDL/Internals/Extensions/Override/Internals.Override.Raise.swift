/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum Raise {
        typealias Closure = @Sendable (Int32) -> Int32

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
            Foundation.raise($0)
        }

        static func replace(with closure: @escaping Closure) {
            self.state.closure = closure
        }

        static func restore() {
            state.closure = defaultClosure
        }
    }
    #endif

    @discardableResult
    static func raise(_ value: Int32) -> Int32 {
        #if DEBUG
        Raise.state.closure(value)
        #else
        Foundation.raise(value)
        #endif
    }
}
