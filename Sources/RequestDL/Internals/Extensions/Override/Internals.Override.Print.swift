/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Override {

    #if DEBUG
    enum Print: Sendable {

        typealias Closure = @Sendable (String, String, Sendable...) -> Void

        @TaskLocal
        fileprivate static var closure: Closure = {
            Swift.print(
                describing($2, separator: $0),
                separator: $0,
                terminator: $1
            )
        }

        static func replace<T: Sendable>(with closure: @escaping Closure, perform: @Sendable () async throws -> T) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    static func print(_ items: Sendable..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Print.closure(separator, terminator, items)
        #else
        Swift.print(
            describing(items, separator: separator),
            separator: separator,
            terminator: terminator
        )
        #endif
    }
}

private func describing(_ items: [Sendable], separator: String) -> String {
    items.map(String.init(describing:)).joined(separator: separator)
}
