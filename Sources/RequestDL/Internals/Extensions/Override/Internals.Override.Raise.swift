//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.Override {

    #if DEBUG
    enum Raise {
        typealias Closure = @Sendable (Int32) -> Int32

        @TaskLocal
        fileprivate static var closure: Closure = {
            #if canImport(FoundationEssentials)
            FoundationEssentials.raise($0)
            #else
            Foundation.raise($0)
            #endif
        }

        @discardableResult
        static func replace<T: Sendable>(
            with closure: @escaping Closure,
            perform: @Sendable () async throws -> T
        ) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    @discardableResult
    static func raise(_ value: Int32) -> Int32 {
        #if DEBUG
        Raise.closure(value)
        #else
        Foundation.raise(value)
        #endif
    }
}
