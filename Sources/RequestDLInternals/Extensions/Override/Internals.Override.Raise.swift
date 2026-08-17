//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
@preconcurrency import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WinSDK)
import WinSDK
#endif

extension Internals.Override {

    #if DEBUG
    /// Swaps out `raise(_:)` for the duration of an operation.
    ///
    /// Task local, so a replacement is visible to the operation and to everything it awaits,
    /// and to nothing running in parallel beside it.
    package enum Raise {

        package typealias Closure = @Sendable (Int32) -> Int32

        // Note the qualified call. Unqualified `raise` here resolves to
        // `Internals.Override.raise(_:)`, the very function this closure backs, which recurses
        // until the stack runs out.
        @TaskLocal
        fileprivate static var closure: Closure = {
            Internals.Override.systemRaise($0)
        }

        @discardableResult
        package static func replace<T: Sendable>(
            with closure: @escaping Closure,
            perform: @Sendable () async throws -> T
        ) async rethrows -> T {
            try await $closure.withValue(closure, operation: perform)
        }

        /// The synchronous counterpart, matching ``Internals/Override/FatalError`` and
        /// ``Internals/Override/AssertionFailure``, which both already had one.
        @discardableResult
        package static func replace<T>(
            with closure: @escaping Closure,
            perform: @Sendable () throws -> T
        ) rethrows -> T {
            try $closure.withValue(closure, operation: perform)
        }
    }
    #endif

    /// Sends a signal to the current process, or to whatever a test has substituted for it.
    ///
    /// - Returns: Zero on success, non zero otherwise, as the C function does.
    @discardableResult
    package static func raise(_ value: Int32) -> Int32 {
        #if DEBUG
        return Raise.closure(value)
        #else
        return systemRaise(value)
        #endif
    }

    /// The real signal call, module qualified so it cannot resolve back to ``raise(_:)``.
    fileprivate static func systemRaise(_ value: Int32) -> Int32 {
        #if canImport(Darwin)
        return Darwin.raise(value)
        #elseif canImport(Android)
        return Android.raise(value)
        #elseif canImport(Glibc)
        return Glibc.raise(value)
        #elseif canImport(Musl)
        return Musl.raise(value)
        #elseif canImport(WinSDK)
        return WinSDK.raise(value)
        #else
        #error("No signal implementation available for this platform")
        #endif
    }
}
