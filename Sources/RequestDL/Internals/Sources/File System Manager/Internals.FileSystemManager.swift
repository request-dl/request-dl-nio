//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOFileSystem
import NIOPosix

extension Internals {

    /// Owns the thread pool `Internals.fileSystem` runs blocking file work on.
    ///
    /// ## Why not `NIOFileSystem.FileSystem.shared`
    ///
    /// `.shared` runs on `NIOSingletons.posixBlockingThreadPool`, a thread pool shared by the
    /// whole process and sized to `System.coreCount` by default — the same size class as Swift
    /// Concurrency's cooperative pool. Under `swift-testing`'s parallel execution, with many
    /// suites each opening their own cache/buffer file at once, that pool saturates the same way
    /// the cooperative pool did before `Internals.FileStreamBuffer` moved off it: not because any
    /// single read or write is slow, but because `Internals.Buffer.Storage` budgets 5s for the
    /// whole open-seek-transfer sequence, and several individually-fast calls each queuing for a
    /// turn on an undersized shared pool can add up past that in aggregate.
    ///
    /// A pool sized for this package's own usage, rather than the process-wide default, fixes
    /// that without reaching for `NIOSingletons.blockingPoolThreadCountSuggestion` — which is a
    /// one-shot, process-global setting a library has no business imposing on whatever else the
    /// host application uses NIO's shared pool for.
    enum FileSystemManager {

        // MARK: - Internal static properties

        static let shared: NIOFileSystem.FileSystem = {
            let threadPool = NIOThreadPool(numberOfThreads: Swift.max(16, System.coreCount * 4))
            threadPool.start()
            return NIOFileSystem.FileSystem(threadPool: threadPool)
        }()
    }

    /// The file system every blocking file operation in `Internals` goes through.
    static var fileSystem: NIOFileSystem.FileSystem {
        FileSystemManager.shared
    }
}
