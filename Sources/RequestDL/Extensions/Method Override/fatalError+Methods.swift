//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if DEBUG
func fatalError(
    _ message: @autoclosure () -> String = String(),
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    FatalError.closure(message(), file, line)
}

enum FatalError {
    typealias FatalErrorClosure = (String, StaticString, UInt) -> Never

    fileprivate static var closure: FatalErrorClosure = defaultClosure

    private static let defaultClosure: FatalErrorClosure = {
        Swift.fatalError($0, file: $1, line: $2)
    }

    static func replace(with closure: @escaping FatalErrorClosure) {
        self.closure = closure
    }

    static func restoreFatalError() {
        closure = defaultClosure
    }
}
#endif
