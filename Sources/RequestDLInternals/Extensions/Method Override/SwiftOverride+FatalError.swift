/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension SwiftOverride {

    #if DEBUG
    public enum FatalError {

        typealias Closure = (String, StaticString, UInt) -> Never

        fileprivate static var closure: Closure = defaultClosure

        private static let defaultClosure: Closure = {
            Swift.fatalError($0, file: $1, line: $2)
        }

        static func replace(with closure: @escaping Closure) {
            self.closure = closure
        }

        static func restoreFatalError() {
            closure = defaultClosure
        }
    }
    #endif

    public static func fatalError(
        _ message: @autoclosure () -> String = String(),
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