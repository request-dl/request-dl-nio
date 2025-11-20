/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

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
            get { _memoryStorage }
            set { _memoryStorage = newValue }
        }

        var diskStorage: DiskStorage {
            get { _diskStorage }
            set { _diskStorage = newValue }
        }

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

    // MARK: - Inits

    /**
     Initializes a data cache with specified memory and disk capacities and a file URL for disk storage.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the data cache.
        - diskCapacity: The maximum disk capacity in bytes for the data cache.
        - url: The file URL representing the location for disk storage.
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        url: URL
    ) {
        self.init(url: url)

        let isMemoryLowerThatAlreadySet = memoryCapacity > .zero && memoryCapacity < storage.memoryCapacity

        let isDiskLowerThatAlreadySet = diskCapacity > .zero && diskCapacity < storage.diskCapacity

        if isMemoryLowerThatAlreadySet || isDiskLowerThatAlreadySet {
            #if DEBUG
            Logger.current.info(
                .loweringCacheCapacityOnInitNotPermitted(
                    memoryCapacity,
                    diskCapacity
                )
            )
            #endif
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
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        suiteName: String
    ) {
        self.init(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            url: Self.temporaryURL(suiteName: suiteName)
        )
    }

    /**
     Initializes a data cache with specified memory and disk capacities.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the data cache.
        - diskCapacity: The maximum disk capacity in bytes for the data cache.
     */
    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero
    ) {
        self.init(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            url: Self.mainTemporaryURL()
        )
    }

    init(url: URL) {
        let url = url
            .deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent, isDirectory: true)

        self.storage = Manager.shared.storage(url)
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

        storage.memoryStorage.remove(key)
        storage.diskStorage.remove(key)
    }

    /**
     Removes all cached data from the cache.
     */
    public func removeAll() {
        storage.memoryStorage.removeAll()
        storage.diskStorage.removeAll()
    }

    /**
     Removes all cached data from the cache that was stored since a specified date.

     - Parameter date: The date to filter cached data removal.
     */
    public func removeAll(since date: Date) {
        storage.memoryStorage.removeAll(since: date)
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

        if cachedResponse.policy.contains(.memory) {
            storage.memoryStorage.updateCached(
                key: key,
                cachedResponse: cachedResponse,
                maximumCapacity: memoryCapacity
            )
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

        var memoryBuffer: Internals.AnyBuffer?
        var diskBuffer: Internals.AnyBuffer?

        if cachedResponse.policy.contains(.memory) {
            memoryBuffer = storage.memoryStorage.allocateBuffer(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength,
                maximumCapacity: memoryCapacity
            )
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

    // MARK: - Private methods

    private func base64EncodedKey(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
