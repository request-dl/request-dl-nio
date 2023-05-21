/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct DataCache: Sendable {

    private class Manager: @unchecked Sendable {

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

        private let directory: URL

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

    // MARK: - Public properties

    public var memoryCapacity: UInt64 {
        get { storage.memoryCapacity }
        nonmutating set { storage.memoryCapacity = newValue }
    }

    public var diskCapacity: UInt64 {
        get { storage.diskCapacity }
        nonmutating set { storage.diskCapacity = newValue }
    }

    // MARK: - Private properties

    private let storage: Storage

    // MARK: - Internal properties

    public init(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        url: URL
    ) {
        self.init(url: url)

        let isMemoryLowerThatAlreadySet = memoryCapacity > .zero && memoryCapacity < storage.memoryCapacity

        let isDiskLowerThatAlreadySet = diskCapacity > .zero && diskCapacity < storage.diskCapacity

        if isMemoryLowerThatAlreadySet || isDiskLowerThatAlreadySet {
            Internals.Log.warning(
                .loweringCacheCapacityOnInitNotPermitted(
                    memoryCapacity,
                    diskCapacity
                )
            )
        }

        storage.memoryCapacity = max(memoryCapacity, storage.memoryCapacity)
        storage.diskCapacity = max(diskCapacity, storage.diskCapacity)
    }

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
        self.storage = Manager.shared.storage(url)
    }

    // MARK: - Internal static methods

    static func temporaryURL(suiteName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.request-dl.Swift.Cache")
            .appendingPathComponent(
                suiteName.replacingOccurrences(
                    of: "[/:\\\\]",
                    with: "_",
                    options: .regularExpression
                )
        )
    }

    static func mainTemporaryURL() -> URL {
        temporaryURL(
            suiteName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        )
    }

    // MARK: - Public methods

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

    public func setCachedData(_ cachedData: CachedData, forKey key: String) {
        var buffer = allocateBuffer(
            key: key,
            cachedResponse: cachedData.cachedResponse,
            contentLength: UInt64(cachedData.buffer.readableBytes)
        )

        buffer?.writeBuffer(cachedData.buffer)
    }

    public func remove(forKey key: String) {
        let key = base64EncodedKey(key)

        storage.memoryStorage.remove(key)
        storage.diskStorage.remove(key)
    }

    public func removeAll() {
        storage.memoryStorage.removeAll()
        storage.diskStorage.removeAll()
    }

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

    func base64EncodedKey(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
