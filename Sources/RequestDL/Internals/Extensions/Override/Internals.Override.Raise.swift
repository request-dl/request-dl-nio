/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum Raise {
        typealias Closure = (Int32) -> Int32

        fileprivate static var closure: Closure = defaultClosure

        private static let defaultClosure: Closure = {
            Foundation.raise($0)
        }

        static func replace(with closure: @escaping Closure) {
            self.closure = closure
        }

        static func restore() {
            closure = defaultClosure
        }
    }
    #endif

    @discardableResult
    static func raise(_ value: Int32) -> Int32 {
        #if DEBUG
        Raise.closure(value)
        #else
        Foundation.raise(value)
        #endif
    }
}
