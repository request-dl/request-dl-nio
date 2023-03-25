/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@discardableResult
public func raise(_ value: Int32) -> Int32 {
    Raise.closure(value)
}

public enum Raise {
    public typealias RaiseClosure = (Int32) -> Int32

    fileprivate static var closure: RaiseClosure = defaultClosure

    private static let defaultClosure: RaiseClosure = {
        Foundation.raise($0)
    }

    public static func replace(with closure: @escaping RaiseClosure) {
        self.closure = closure
    }

    public static func restoreRaise() {
        closure = defaultClosure
    }
}
