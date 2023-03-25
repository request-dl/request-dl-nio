/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if DEBUG
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    Print.closure(items, separator, terminator)
}

public enum Print {
    public typealias PrintClosure = ([Any], String, String) -> Void

    fileprivate static var closure: PrintClosure = defaultClosure

    private static let defaultClosure: PrintClosure = {
        let output = $0
            .map { "\($0)" }
            .joined(separator: $1)
            .appending($2)

        Swift.print(output, separator: "", terminator: "")
    }

    public static func replace(with closure: @escaping PrintClosure) {
        self.closure = closure
    }

    public static func restoreRaise() {
        closure = defaultClosure
    }
}
#endif
