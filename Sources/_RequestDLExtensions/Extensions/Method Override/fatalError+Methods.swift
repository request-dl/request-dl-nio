/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if DEBUG
public func fatalError(
    _ message: @autoclosure () -> String = String(),
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    FatalError.closure(message(), file, line)
}

public enum FatalError {
    public typealias FatalErrorClosure = (String, StaticString, UInt) -> Never

    fileprivate static var closure: FatalErrorClosure = defaultClosure

    private static let defaultClosure: FatalErrorClosure = {
        Swift.fatalError($0, file: $1, line: $2)
    }

    public static func replace(with closure: @escaping FatalErrorClosure) {
        self.closure = closure
    }

    public static func restoreFatalError() {
        closure = defaultClosure
    }
}
#endif
