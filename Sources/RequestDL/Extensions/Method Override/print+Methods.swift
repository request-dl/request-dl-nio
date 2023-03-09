//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if DEBUG
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    Print.closure(items, separator, terminator)
}

enum Print {
    typealias PrintClosure = ([Any], String, String) -> Void

    fileprivate static var closure: PrintClosure = defaultClosure

    private static let defaultClosure: PrintClosure = {
        let output = $0
            .map { "\($0)" }
            .joined(separator: $1)
            .appending($2)

        Swift.print(output)
    }

    static func replace(with closure: @escaping PrintClosure) {
        self.closure = closure
    }

    static func restoreRaise() {
        closure = defaultClosure
    }
}
#endif
