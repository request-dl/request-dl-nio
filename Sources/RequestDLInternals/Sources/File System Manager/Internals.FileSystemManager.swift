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

        // MARK: - Private static properties

        private static let threadPool = PortableBlockingPool(
            threadCount: Swift.max(16, ProcessInfo.processInfo.activeProcessorCount * 4)
        )

        // MARK: - Internal static methods

        /// Same contract as the `NIOThreadPool`-backed overload above, ported to a build without
        /// NIO: still never runs a blocking file syscall on whichever Swift Concurrency
        /// cooperative thread happens to call in here, since that is what the watchdog-false-
        /// positive problem this type exists to solve actually turns on, not `NIOThreadPool`
        /// specifically.
        ///
        /// `DispatchQueue.global()` looked like an equivalent elastic worker pool at first, since
        /// it is already outside Swift Concurrency's fixed-size cooperative pool, and earlier
        /// versions of this method dispatched onto it directly instead of building a dedicated
        /// pool by hand the way `NIOThreadPool(numberOfThreads:)` does above. That queue is
        /// shared by everything else in the process, though, and under `swift-testing`'s parallel
        /// execution -- a sudden burst of hundreds of suites each opening their own file at
        /// once -- its own ramp-up lag was directly observed adding up past
        /// `Internals.Buffer.Storage`'s per-operation budget in aggregate on CI macOS runners: the
        /// exact failure mode this comment's first paragraph already describes the NIOCore side
        /// needing a dedicated pool to avoid. `PortableBlockingPool` below is that same fix,
        /// ported without NIO: real OS threads that never return to GCD's shared pool for
        /// anything else, sized the same way (`max(16, coreCount * 4)`).
        package static func run<T: Sendable>(
            _ body: @escaping @Sendable () throws -> T
        ) async throws -> T {
            try await threadPool.run(body)
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

#if !canImport(NIOCore)

/// A fixed-size pool of dedicated OS threads for blocking file work, ported without NIO. See
/// `Internals.FileSystemManager.run`'s doc comment for why this exists instead of
/// `DispatchQueue.global()`: threads started here only ever run work handed to this pool, so
/// they cannot be starved by unrelated `.utility`-queue work elsewhere in the process the way a
/// shared GCD queue's own worker ramp-up was observed to under heavy concurrent test load.
private final class PortableBlockingPool: @unchecked Sendable {

    // MARK: - Private properties

    private let condition = NSCondition()
    private var workItems: [() -> Void] = []

    // MARK: - Inits

    init(threadCount: Int) {
        for index in 0..<threadCount {
            let thread = Thread { [self] in
                _runLoop()
            }
            thread.name = "com.requestdl.portable-blocking-pool.\(index)"
            // Matches the default main thread stack size. The work run here is plain,
            // non-recursive file I/O, so the platform default has never been a constraint; this
            // just avoids inheriting whatever (possibly much smaller) stack size the thread that
            // happens to construct this pool was given.
            thread.stackSize = 1 << 20
            thread.start()
        }
    }

    // MARK: - Internal methods

    /// Runs `body` on this pool and suspends the calling task until it completes.
    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            condition.lock()
            workItems.append {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            condition.signal()
            condition.unlock()
        }
    }

    // MARK: - Private methods

    /// Body of every thread this pool starts. Never returns, matching every other fixed-size
    /// thread pool: the thread exists for exactly as long as the process does.
    private func _runLoop() {
        while true {
            condition.lock()

            while workItems.isEmpty {
                condition.wait()
            }

            let workItem = workItems.removeFirst()
            condition.unlock()

            workItem()
        }
    }
}

#endif
