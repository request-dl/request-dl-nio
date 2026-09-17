//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOCore
import NIOFileSystem
import NIOPosix
#else
import Foundation
#endif

extension Internals {

    /// Owns the thread pool `Internals.fileSystem` runs blocking file work on.
    ///
    /// ## Why not `NIOFileSystem.FileSystem.shared`
    ///
    /// `.shared` runs on `NIOSingletons.posixBlockingThreadPool`, a thread pool shared by the
    /// whole process and sized to `System.coreCount` by default (the same size class as Swift
    /// Concurrency's cooperative pool). Under `swift-testing`'s parallel execution, with many
    /// suites each opening their own cache/buffer file at once, that pool saturates the same way
    /// the cooperative pool did before `Internals.FileStreamBuffer` moved off it: not because any
    /// single read or write is slow, but because `Internals.Buffer.Storage` budgets 5s for the
    /// whole open-seek-transfer sequence, and several individually-fast calls each queuing for a
    /// turn on an undersized shared pool can add up past that in aggregate.
    ///
    /// A pool sized for this package's own usage, rather than the process-wide default, fixes
    /// that without reaching for `NIOSingletons.blockingPoolThreadCountSuggestion`, which is a
    /// one-shot, process-global setting a library has no business imposing on whatever else the
    /// host application uses NIO's shared pool for.
    package enum FileSystemManager {

        #if canImport(NIOCore)

        // MARK: - Private static properties

        private static let threadPool: NIOThreadPool = {
            let threadPool = NIOThreadPool(numberOfThreads: Swift.max(16, System.coreCount * 4))
            threadPool.start()
            return threadPool
        }()

        // MARK: - Internal static properties

        package static let shared: NIOFileSystem.FileSystem = {
            NIOFileSystem.FileSystem(threadPool: threadPool)
        }()

        // MARK: - Internal static methods

        /// Runs a blocking, non-`NIOFileSystem` file operation on the same pool every other
        /// blocking file operation in `Internals` uses, rather than whichever Swift Concurrency
        /// cooperative thread happens to call in here. See `FileStreamBuffer`'s doc for why that
        /// distinction matters under `swift-testing`'s parallel execution.
        ///
        /// - Note: Exists for platform-specific calls `NIOFileSystem` has no notion of (Darwin's
        /// file protection attributes) that still touch the same files this pool already owns.
        package static func run<T: Sendable>(
            _ body: @escaping @Sendable () throws -> T
        ) async throws -> T {
            try await threadPool.runIfActive(body)
        }

        #else

        // MARK: - Internal static methods

        /// Same contract as the `NIOThreadPool`-backed overload above, ported to a build without
        /// NIO: still never runs a blocking file syscall on whichever Swift Concurrency
        /// cooperative thread happens to call in here, since that is what the watchdog-false-
        /// positive problem this type exists to solve actually turns on, not `NIOThreadPool`
        /// specifically. `DispatchQueue.global()` is GCD's own elastic worker pool: entirely
        /// outside Swift Concurrency's fixed-size cooperative pool already, so no dedicated pool
        /// needs to be built by hand the way `NIOThreadPool(numberOfThreads:)` is above.
        package static func run<T: Sendable>(
            _ body: @escaping @Sendable () throws -> T
        ) async throws -> T {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try body())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        #endif
    }

    /// The file system every blocking file operation in `Internals` goes through.
    #if canImport(NIOCore)
    package static var fileSystem: NIOFileSystem.FileSystem {
        FileSystemManager.shared
    }
    #else
    package static var fileSystem: PortableFileSystem.Type {
        PortableFileSystem.self
    }
    #endif
}
