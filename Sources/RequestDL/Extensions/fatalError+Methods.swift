//
//  File.swift
//  
//
//  Created by Brenno on 08/03/23.
//

import Foundation

func fatalError(_ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) -> Never {
    FatalError.closure(message(), file, line)
}

/// Utility functions that can replace and restore the `fatalError` global function.
enum FatalError {
    typealias FatalErrorClosure = (String, StaticString, UInt) -> Never

    static var closure: FatalErrorClosure = defaultClosure

    private static let defaultClosure: FatalErrorClosure = { Swift.fatalError($0, file: $1, line: $2) }

    static func replace(with closure: @escaping FatalErrorClosure) {
        self.closure = closure
    }

    /// Restore the `fatalError` global function back to the original Swift implementation
    static func restoreFatalError() {
        closure = defaultClosure
    }
}
