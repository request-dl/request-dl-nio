/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension SwiftOverride {

    #if DEBUG
    enum Print {
        typealias Closure = (String, String, Any...) -> Void

        fileprivate static var closure: Closure = defaultClosure

        private static let defaultClosure: Closure = {
            Swift.print($2, separator: $0, terminator: $1)
        }

        static func replace(with closure: @escaping Closure) {
            self.closure = closure
        }

        static func restoreRaise() {
            closure = defaultClosure
        }
    }
    #endif

    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Print.closure(separator, terminator, items)
        #else
        Swift.print(items, separator: separator, terminator: terminator)
        #endif
    }
}
