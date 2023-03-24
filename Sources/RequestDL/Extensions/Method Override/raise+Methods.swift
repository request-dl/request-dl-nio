/*
 See LICENSE for this package's licensing information.
*/

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@discardableResult
func raise(_ value: Int32) -> Int32 {
    Raise.closure(value)
}

enum Raise {
    typealias RaiseClosure = (Int32) -> Int32

    fileprivate static var closure: RaiseClosure = defaultClosure

    private static let defaultClosure: RaiseClosure = {
        Darwin.raise($0)
    }

    static func replace(with closure: @escaping RaiseClosure) {
        self.closure = closure
    }

    static func restoreRaise() {
        closure = defaultClosure
    }
}
