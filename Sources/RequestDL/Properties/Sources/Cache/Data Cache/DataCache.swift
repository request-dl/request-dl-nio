/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging
import SwiftAsyncStream

/**
 A data cache that stores and retrieves data based on specified capacities and policies.
 */
public struct DataCache: Sendable, Equatable {

    private final class Manager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = Manager()

        // MARK: - Private properties

        private let lock = Lock()

        private var storages: [URL: DataCache.Storage] = [:]

        // MARK: - Internal methods

        func storage(_ url: URL) -> DataCache.Storage {
            lock.withLock {
                if let storage = storages[url] {
                    return storage
                }

                let storage = DataCache.Storage(url)
                storages[url] = storage
                return storage
            }
        }
    }

    private final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var memoryStorage: MemoryStorage {
            lock.withLock { _memoryStorage }
        }

        var diskStorage: DiskStorage {
            lock.withLock { _diskStorage }
        }

        /// Cache writes started and not yet finished.
        let pendingWrites = Internals.PendingTasks(priority: .background)

        var memoryCapacity: UInt64 {
            get { lock.withLock { _memoryCapacity } }
            set { lock.withLock { _memoryCapacity = newValue } }
        }

        var diskCapacity: UInt64 {
            get { lock.withLock { _diskCapacity } }
            set { lock.withLock { _diskCapacity = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        fileprivate let directory: URL

        // MARK: - Unsafe properties

        private var _memoryCapacity: UInt64 {
            didSet {
                if _memoryCapacity < oldValue {
                    _memoryStorage.freeSpace(_memoryCapacity)
                }
            }
        }

        private var _diskCapacity: UInt64 {
            didSet {
                if _diskCapacity < oldValue {
                    _diskStorage.freeSpace(_diskCapacity)
                }
            }
        }

        private var _memoryStorage: MemoryStorage
        private var _diskStorage: DiskStorage

        // MARK: - Internal methods

        /// Mutates the memory tier inside a single critical section.
        ///
        /// `MemoryStorage` is a struct whose mutating methods would otherwise be reached
        /// through a computed property, making every call a read, a modify and a write across
        /// two separate lock acquisitions. Two concurrent cache writes can lose each other's
        /// records that way.
        ///
        /// - Warning: The lock is not reentrant. Do not touch any other property of this
        /// storage from inside `body`, including the capacities.
        func withMemoryStorage<Output>(_ body: (inout MemoryStorage) -> Output) -> Output {
            lock.withLock { body(&_memoryStorage) }
        }

        // MARK: - Init

        init(_ directory: URL) {
            self.directory = directory
            self._memoryStorage = .init(directory: directory)
            self._diskStorage = .init(directory: directory)
            self._memoryCapacity = .zero
            self._diskCapacity = .zero
        }
    }

    // MARK: - Public static properties

    public static let shared = DataCache()

    // MARK: - Public properties

    /**
     The maximum memory capacity in bytes for the data cache.
     */
    public var memoryCapacity: UInt64 {
        get { storage.memoryCapacity }
        nonmutating set { storage.memoryCapacity = newValue }
    }

    /**
     The maximum disk capacity in bytes for the data cache.
     */
    public var diskCapacity: UInt64 {
        get { storage.diskCapacity }
        nonmutating set { storage.diskCapacity = newValue }
    }

    // MARK: - Internal properties

    var directoryURL: URL {
        storage.directory
    }

    // MARK: - Private properties

    private let storage: Storage
    private let logger: Logger?

    // MARK: - Inits

    /**
     Initializes a data cache with specified memory and disk capacities and a file URL for disk storage.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the data cache.
        - diskCapacity: The maximum disk capacity in bytes for the data cache.
        - url: The file URL representing the location for disk storage.
        - logger: The logger for cache usage.
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        url: URL,
        logger: Logger? = nil
    ) {
        self.init(url: url, logger: logger)

        let isMemoryLowerThatAlreadySet = memoryCapacity > .zero && memoryCapacity < storage.memoryCapacity

        let isDiskLowerThatAlreadySet = diskCapacity > .zero && diskCapacity < storage.diskCapacity

        if isMemoryLowerThatAlreadySet || isDiskLowerThatAlreadySet {
            Internals.Log.loweringCacheCapacityOnInitNotPermitted(
                memoryCapacity,
                diskCapacity
            ).log(level: .info, logger: logger)
        }

        storage.memoryCapacity = max(memoryCapacity, storage.memoryCapacity)
        storage.diskCapacity = max(diskCapacity, storage.diskCapacity)
    }

    /**
     Initializes a data cache with specified memory and disk capacities and a suite name for disk storage.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the data cache.
        - diskCapacity: The maximum disk capacity in bytes for the data cache.
        - suiteName: The name of the shared user defaults suite for disk storage.
        - logger: The logger for cache usage.
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        suiteName: String,
        logger: Logger? = nil
    ) {
        self.init(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            url: Self.temporaryURL(suiteName: suiteName),
            logger: logger
        )
    }

    /**
     Initializes a data cache with specified memory and disk capacities.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the data cache.
        - diskCapacity: The maximum disk capacity in bytes for the data cache.
        - logger: The logger for cache usage.        
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        logger: Logger? = nil
    ) {
        self.init(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            url: Self.mainTemporaryURL(),
            logger: logger
        )
    }

    init(url: URL, logger: Logger? = nil) {
        let url = url
            .deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent, isDirectory: true)

        self.storage = Manager.shared.storage(url)
        self.logger = logger
    }

    // MARK: - Public static methods

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.storage.directory == rhs.storage.directory
    }

    // MARK: - Internal static methods

    static func temporaryURL(suiteName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "com.request-dl-nio.Swift.Cache",
                isDirectory: true
            )
            .appendingPathComponent(
                suiteName.replacingOccurrences(
                    of: "[/:\\\\]",
                    with: "_",
                    options: .regularExpression
                ),
                isDirectory: true
            )
    }

    static func mainTemporaryURL() -> URL {
        temporaryURL(
            suiteName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        )
    }

    // MARK: - Public methods

    /**
     Retrieves cached data for a specified key and policy.

     - Parameters:
        - key: The key associated with the cached data.
        - policy: The policy indicating the desired behavior for retrieving the cached data.
     - Returns: The cached data, if available based on the specified policy.
     */
    public func getCachedData(forKey key: String, policy: DataCache.Policy.Set) -> CachedData? {
        let key = base64EncodedKey(key)

        if policy.contains(.memory), let cachedData = storage.memoryStorage[key] {
            return cachedData
        }

        if policy.contains(.disk) {
            return storage.diskStorage[key]
        }

        return nil
        // Memory is consulted first, which is only safe because `allocateBuffer` evicts the
        // memory entry whenever the memory tier refuses the new one. Without that, a response
        // too large for memory but small enough for disk would leave a stale entry in front of
        // a fresh one.
    }

    /**
     Sets cached data for a specified key.

     - Parameters:
        - cachedData: The cached data to be stored.
        - key: The key associated with the cached data.
     */
    public func setCachedData(_ cachedData: CachedData, forKey key: String) {
        var buffer = allocateBuffer(
            key: key,
            cachedResponse: cachedData.cachedResponse,
            contentLength: UInt64(cachedData.buffer.readableBytes)
        )

        buffer?.writeBuffer(cachedData.buffer)
    }

    /**
     Removes cached data for a specified key.

     - Parameter key: The key associated with the cached data to be removed.
     */
    public func remove(forKey key: String) {
        let key = base64EncodedKey(key)

        storage.withMemoryStorage { $0.remove(key) }
        storage.diskStorage.remove(key)
    }

    /**
     Removes all cached data from the cache.
     */
    public func removeAll() {
        storage.withMemoryStorage { $0.removeAll() }
        storage.diskStorage.removeAll()
    }

    /**
     Removes all cached data from the cache that was stored since a specified date.

     - Parameter date: The date to filter cached data removal.
     */
    public func removeAll(since date: Date) {
        storage.withMemoryStorage { $0.removeAll(since: date) }
        storage.diskStorage.removeAll(since: date)
    }

    // MARK: - Internal methods

    func updateCached(
        key: String,
        cachedResponse: CachedResponse
    ) {
        guard !cachedResponse.policy.isEmpty else {
            return
        }

        let key = base64EncodedKey(key)

        // Read before entering the critical section below: the lock is not reentrant, and
        // these getters take it.
        let memoryCapacity = self.memoryCapacity

        if cachedResponse.policy.contains(.memory) {
            storage.withMemoryStorage {
                $0.updateCached(
                    key: key,
                    cachedResponse: cachedResponse,
                    maximumCapacity: memoryCapacity
                )
            }
        }

        if cachedResponse.policy.contains(.disk) {
            storage.diskStorage.updateCached(
                key: key,
                cachedResponse: cachedResponse,
                maximumCapacity: diskCapacity
            )
        }
    }

    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: UInt64
    ) -> Buffer? {
        guard !cachedResponse.policy.isEmpty else {
            return nil
        }

        let key = base64EncodedKey(key)

        // Read before entering the critical section below: the lock is not reentrant, and
        // these getters take it.
        let memoryCapacity = self.memoryCapacity

        var memoryBuffer: Internals.AnyBuffer?
        var diskBuffer: Internals.AnyBuffer?

        if cachedResponse.policy.contains(.memory) {
            memoryBuffer = storage.withMemoryStorage { memoryStorage -> Internals.AnyBuffer? in
                guard let buffer = memoryStorage.allocateBuffer(
                    key: key,
                    cachedResponse: cachedResponse,
                    contentLength: contentLength,
                    maximumCapacity: memoryCapacity
                ) else {
                    // The memory tier turned the new entry down, usually for size. Dropping
                    // whatever was there keeps `getCachedData` from serving it in front of a
                    // disk entry that is about to be updated.
                    memoryStorage.remove(key)
                    return nil
                }

                return buffer
            }
        }

        if cachedResponse.policy.contains(.disk) {
            diskBuffer = storage.diskStorage.allocateBuffer(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength,
                maximumCapacity: diskCapacity
            )
        }

        return .init(
            memoryBuffer: memoryBuffer,
            diskBuffer: diskBuffer
        )
    }

    /// Runs a cache write and keeps track of it, so `waitUntilIdle()` can join it later.
    func trackWrite(_ operation: @escaping @Sendable () async -> Void) {
        storage.pendingWrites.run(operation)
    }

    /// Suspends until every cache write started so far has finished.
    ///
    /// Caching happens after the caller already has its response, so without this there is no
    /// point at which "the request is done" also means "the cache is written".
    func waitUntilIdle() async {
        await storage.pendingWrites.waitUntilIdle()
    }

    // MARK: - Private methods

    private func base64EncodedKey(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
