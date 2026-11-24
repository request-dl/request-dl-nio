//
// See LICENSE for this package's licensing information.
//

import Crypto
import Logging
import RequestDLInternals
import SwiftAsyncStream
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.ProcessInfo
#endif

#if canImport(Darwin)
import struct Foundation.FileProtectionType
#endif

/// A data cache that stores and retrieves data based on specified capacities and policies.
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

    final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var memoryStorage: MemoryStorage {
            lock.withLock { _memoryStorage }
        }

        var diskStorage: DiskStorage {
            lock.withLock { _diskStorage }
        }

        #if canImport(Darwin)
        var fileProtection: FileProtectionType? {
            get { lock.withLock { _diskStorage.fileProtection } }
            set { lock.withLock { _diskStorage.fileProtection = newValue } }
        }
        #endif

        var encryptionKey: DataCache.EncryptionKey? {
            get { lock.withLock { _diskStorage.encryptionKey } }
            set { lock.withLock { _diskStorage.encryptionKey = newValue } }
        }

        /// Cache writes started and not yet finished.
        ///
        /// Each write runs at the priority of the request that made it (see
        /// ``DataCache/trackWrite(priority:_:)``), not a fixed low one. A write is the reader of a
        /// stream the response feeds, and a lagging one makes the response give up on the cache
        /// (`CacheBacklogExceededError`); while it is unfinished, the key reads as a miss.
        let pendingWrites = Internals.PendingTasks()

        /// Runs `body` while holding the revalidation lock of `key`: see
        /// ``DataCache/renewCached(key:cachedResponse:expecting:policy:)``.
        ///
        /// One lock per key, not one for the whole cache. What the lock protects is one entry
        /// being rewritten and read back, and revalidations of other entries have nothing to do
        /// with it: a single lock queued every revalidation of every URL behind the disk work
        /// (and the body promotion) of the one ahead of it.
        ///
        /// A key's lock exists only while someone holds or waits for it.
        func withRevalidationLock<Value: Sendable>(
            forKey key: String,
            _ body: @Sendable () async -> Value
        ) async -> Value {
            let keyLock = lock.withLock { () -> AsyncLock in
                var entry = _revalidationLocks[key] ?? (lock: AsyncLock(), users: 0)
                entry.users += 1
                _revalidationLocks[key] = entry
                return entry.lock
            }

            let value = await keyLock.withLock { await body() }

            lock.withLock {
                guard var entry = _revalidationLocks[key] else {
                    return
                }

                entry.users -= 1
                _revalidationLocks[key] = entry.users > 0 ? entry : nil
            }

            return value
        }

        /// How many keys have a revalidation lock right now, exposed for tests.
        var revalidationLockCount: Int {
            lock.withLock { _revalidationLocks.count }
        }

        var memoryCapacity: Int64 {
            get { lock.withLock { _memoryCapacity } }
            set {
                // Store and trim in one critical section. Memory eviction is bookkeeping over a
                // struct this lock already owns, so it belongs here.
                lock.withLock {
                    let didShrink = newValue < _memoryCapacity
                    _memoryCapacity = newValue

                    if didShrink {
                        _memoryStorage.freeSpace(newValue)
                    }
                }
            }
        }

        var diskCapacity: Int64 {
            get { lock.withLock { _diskCapacity } }
            set {
                // Disk eviction is file system work and asynchronous, so it cannot happen where
                // the memory one does. It ran from a `didSet`, which cannot await, and which
                // fired from inside this lock anyway.
                //
                // The store stays under the lock; the trim is handed to the same tracker cache
                // writes use, so `waitUntilIdle()` joins it and a test can wait for eviction
                // instead of sleeping.
                let diskStorage: DiskStorage? = lock.withLock {
                    let didShrink = newValue < _diskCapacity
                    _diskCapacity = newValue
                    return didShrink ? _diskStorage : nil
                }

                guard let diskStorage else {
                    return
                }

                // Housekeeping nobody waits for: low priority on purpose, and not inherited from
                // whoever happens to set the capacity.
                pendingWrites.run(priority: .background) {
                    await diskStorage.freeSpace(newValue)
                }
            }
        }

        // MARK: - Private properties

        private let lock = Lock()

        fileprivate let directory: URL

        // MARK: - Unsafe properties

        // Plain storage. Eviction can't hang off `didSet` because one of the two storages is
        // asynchronous and an observer cannot await. It lives in the setters above instead, which
        // keeps the pair symmetrical and makes it visible that only shrinking evicts.
        private var _memoryCapacity: Int64
        private var _diskCapacity: Int64

        private var _memoryStorage: MemoryStorage
        private var _diskStorage: DiskStorage

        private var _revalidationLocks: [String: (lock: AsyncLock, users: Int)] = [:]

        /// Best-effort disk usage estimate, `nil` until first reconciled.
        ///
        /// Only a hint for `DiskStorage.freeSpace(_:knownUsage:)` to skip its directory rescan on
        /// writes that are nowhere near capacity; it is never relied on for correctness. It's left
        /// untouched by `remove`/`removeAll`/capacity changes, since those only move usage down or
        /// reset it, so a stale estimate costs at worst one avoidable rescan.
        private var _diskUsageEstimate: Int64?

        /// Same role as `_diskUsageEstimate`, for `MemoryStorage.freeSpace(_:knownUsage:)`. See
        /// that method's doc for the safety argument.
        private var _memoryUsageEstimate: Int64?

        /// How many writes are in progress for each key. Guarded by `lock`.
        private var _writesInProgress: [String: Int] = [:]

        /// Keys whose entry is being read from the disk tier to be kept in the memory tier. The
        /// value says whether what was read is still what the cache holds: any write, revalidation
        /// or removal of the key since the read began sets it to `false`. Guarded by `lock`.
        private var _promotions: [String: Bool] = [:]

        // MARK: - Internal methods

        /// Starts a write for `key`: until the token ends, ``isWriting(key:)`` answers `true`.
        func beginWrite(key: String) -> WriteToken {
            lock.withLock {
                _writesInProgress[key, default: 0] += 1

                if _promotions[key] != nil {
                    _promotions[key] = false
                }
            }

            return WriteToken { [weak self] in self?.endWrite(key: key) }
        }

        fileprivate func endWrite(key: String) {
            lock.withLock {
                guard let count = _writesInProgress[key] else {
                    return
                }

                _writesInProgress[key] = count > 1 ? count - 1 : nil
            }
        }

        /// Starts reading `key` from the disk tier to keep it in memory. Answers `false` when
        /// there is nothing to do: the key is being written, is already in memory, or is already
        /// being promoted by another reader.
        func beginPromotion(key: String) -> Bool {
            lock.withLock {
                guard
                    _writesInProgress[key] == nil,
                    _promotions[key] == nil,
                    !_memoryStorage.contains(key)
                else {
                    return false
                }

                _promotions[key] = true
                return true
            }
        }

        func cancelPromotion(key: String) {
            lock.withLock { _promotions[key] = nil }
        }

        /// Marks what a promotion of `key` has read as out of date.
        func invalidatePromotion(key: String) {
            lock.withLock {
                if _promotions[key] != nil {
                    _promotions[key] = false
                }
            }
        }

        func invalidateAllPromotions() {
            lock.withLock {
                for key in _promotions.keys {
                    _promotions[key] = false
                }
            }
        }

        /// Keeps what a promotion read, unless the cache changed under it.
        ///
        /// - Returns: Whether the entry is now in the memory tier.
        func finishPromotion(
            key: String,
            cachedResponse: CachedResponse,
            dataURL: Internals.ByteURL
        ) -> Bool {
            lock.withLock {
                let isCurrent = _promotions.removeValue(forKey: key) ?? false

                guard isCurrent, _writesInProgress[key] == nil, !_memoryStorage.contains(key) else {
                    return false
                }

                let (installed, usage) = _memoryStorage.install(
                    key: key,
                    cachedResponse: cachedResponse,
                    dataURL: dataURL,
                    maximumCapacity: _memoryCapacity,
                    knownUsage: _memoryUsageEstimate
                )

                if let usage {
                    _memoryUsageEstimate = usage
                }

                return installed
            }
        }

        func isWriting(key: String) -> Bool {
            lock.withLock { _writesInProgress[key] != nil }
        }

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

        /// Allocates a memory buffer's backing store, reusing `_memoryUsageEstimate` so a write
        /// nowhere near capacity can skip `MemoryStorage.freeSpace`'s scan. See that method and
        /// `_memoryUsageEstimate`'s doc for the safety argument behind reusing this estimate.
        ///
        /// Fully synchronous, unlike `allocateDiskBuffer`'s two-part split: `MemoryStorage`'s own
        /// `allocateBuffer` cannot `await` either (see its doc comment), so reading capacity/
        /// usage, mutating storage, and writing the fresh usage estimate back all happen in one
        /// lock acquisition here.
        func allocateMemoryDataURL(
            key: String,
            cachedResponse: CachedResponse,
            contentLength: Int64
        ) -> (dataURL: Internals.ByteURL, replaced: MemoryStorage.Record?)? {
            lock.withLock {
                let (dataURL, usage, replaced) = _memoryStorage.allocateBufferReplacing(
                    key: key,
                    cachedResponse: cachedResponse,
                    contentLength: contentLength,
                    maximumCapacity: _memoryCapacity,
                    knownUsage: _memoryUsageEstimate
                )

                guard let dataURL else {
                    // The memory tier turned the new entry down, usually for size. Dropping
                    // whatever was there keeps `getCachedData` from serving it in front of a
                    // disk entry that is about to be updated.
                    _memoryStorage.remove(key)
                    return nil
                }

                _memoryUsageEstimate = usage
                return (dataURL, replaced)
            }
        }

        /// Allocates a disk buffer, reusing `_diskUsageEstimate` so a write nowhere near
        /// capacity can skip `DiskStorage.freeSpace`'s directory rescan. See that method and
        /// `_diskUsageEstimate`'s doc for the safety argument behind reading and writing this
        /// estimate outside the lock that guards it.
        func allocateDiskBuffer(
            key: String,
            cachedResponse: CachedResponse,
            contentLength: Int64
        ) async -> (buffer: Internals.AnyBuffer?, recordURL: URL?) {
            let (diskStorage, maximumCapacity, knownUsage) = lock.withLock {
                (_diskStorage, _diskCapacity, _diskUsageEstimate)
            }

            let (buffer, usage, recordURL) = await diskStorage.allocateBuffer(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength,
                maximumCapacity: maximumCapacity,
                knownUsage: knownUsage
            )

            if let usage {
                lock.withLock { _diskUsageEstimate = usage }
            }

            return (buffer, recordURL)
        }

        /// Rewrites the response record of a disk entry, reusing `_diskUsageEstimate` so that a
        /// renewal nowhere near capacity does not measure the whole directory, and moving the
        /// estimate by what the record grew.
        func updateDiskCached(
            key: String,
            cachedResponse: CachedResponse,
            expecting expected: CachedResponse
        ) async {
            let (diskStorage, maximumCapacity, knownUsage) = lock.withLock {
                (_diskStorage, _diskCapacity, _diskUsageEstimate)
            }

            let growth = await diskStorage.updateCached(
                key: key,
                cachedResponse: cachedResponse,
                expecting: expected,
                maximumCapacity: maximumCapacity,
                knownUsage: knownUsage
            )

            guard growth != .zero else {
                return
            }

            lock.withLock {
                if let estimate = _diskUsageEstimate {
                    _diskUsageEstimate = estimate + growth
                }
            }
        }

        /// Corrects `_memoryUsageEstimate` after a write finishes, replacing the `contentLength`
        /// hint `allocateMemoryDataURL` folded in at allocation time with the delta between that
        /// hint and the buffer's real byte count.
        ///
        /// The hint is `0` for any response with no accurate `Content-Length` (chunked transfer
        /// is the common case, since the two are mutually exclusive per HTTP semantics), while
        /// the actual write can be arbitrarily larger. Left unreconciled, the estimate would
        /// permanently undercount such a write, and `MemoryStorage.freeSpace`'s `knownUsage`
        /// short-circuit would keep trusting that undercount forever, letting the
        /// memory tier grow past `memoryCapacity` indefinitely across repeated chunked writes.
        func reconcileMemoryUsage(contentLengthHint: Int64, actualSize: Int64) {
            guard actualSize != contentLengthHint else { return }

            lock.withLock {
                guard let estimate = _memoryUsageEstimate else { return }
                _memoryUsageEstimate = estimate - contentLengthHint + actualSize
            }
        }

        /// Same role as `reconcileMemoryUsage(contentLengthHint:actualSize:)`, for
        /// `_diskUsageEstimate`.
        func reconcileDiskUsage(contentLengthHint: Int64, actualSize: Int64) {
            guard actualSize != contentLengthHint else { return }

            lock.withLock {
                guard let estimate = _diskUsageEstimate else { return }
                _diskUsageEstimate = estimate - contentLengthHint + actualSize
            }
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

    ///
    /// The maximum memory capacity in bytes for the data cache.
    ///
    public var memoryCapacity: Int64 {
        get { storage.memoryCapacity }
        nonmutating set { storage.memoryCapacity = newValue }
    }

    ///
    /// The maximum disk capacity in bytes for the data cache.
    ///
    public var diskCapacity: Int64 {
        get { storage.diskCapacity }
        nonmutating set { storage.diskCapacity = newValue }
    }

    #if canImport(Darwin)
    ///
    /// The Data Protection class applied to newly written disk cache files.
    ///
    /// `nil`, the default, leaves the system default protection class in place. Setting it only
    /// affects cache entries written from that point on; existing files keep their class.
    ///
    /// `.completeUntilFirstUserAuthentication` is the usual choice for a cache: it keeps entries
    /// unreadable before the device's first unlock after boot, without the stricter classes'
    /// risk of a background write or read failing outright while the device is locked.
    ///
    public var fileProtection: FileProtectionType? {
        get { storage.fileProtection }
        nonmutating set { storage.fileProtection = newValue }
    }
    #endif

    ///
    /// The key used to encrypt the disk tier at rest.
    ///
    /// `nil`, the default, leaves the disk tier unencrypted. Setting it only affects cache
    /// entries written from that point on; existing plaintext files are left alone. Supplying a
    /// new key does not invalidate entries written under a previous one: they fail to decrypt,
    /// are treated as misses, and are re-encrypted under the current key the next time they're
    /// written. See ``removeAll()`` for clearing the cache outright, e.g. after a suspected key
    /// compromise.
    ///
    public var encryptionKey: DataCache.EncryptionKey? {
        get { storage.encryptionKey }
        nonmutating set { storage.encryptionKey = newValue }
    }

    // MARK: - Internal properties

    var directoryURL: URL {
        storage.directory
    }

    // MARK: - Private properties

    let storage: Storage
    private let logger: Logger?

    // MARK: - Inits

    ///
    /// Initializes a data cache with specified memory and disk capacities and a file URL for disk storage.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the data cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the data cache.
    ///    - url: The file URL representing the location for disk storage.
    ///    - logger: The logger for cache usage.
    ///
    public init(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
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

    ///
    /// Initializes a data cache with specified memory and disk capacities and a suite name for disk storage.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the data cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the data cache.
    ///    - suiteName: The name of the shared user defaults suite for disk storage.
    ///    - logger: The logger for cache usage.
    ///
    public init(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
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

    ///
    /// Initializes a data cache with specified memory and disk capacities.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the data cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the data cache.
    ///    - logger: The logger for cache usage.
    ///
    public init(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
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
        let url =
            url
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

    /// The cache directory for a given suite.
    ///
    /// - Note: Resolved through ``SystemPackage/FilePath/cachesDirectory``, not
    /// `FilePath.temporaryDirectory``. Cache entries are meant to survive between requests, and
    /// the temporary directory offers no such guarantee: the system can purge it at any moment,
    /// even while the app is running. `cachesDirectory` lands in `Library/Caches` on Darwin,
    /// which is only cleared between launches. On Linux it is the user's XDG cache directory.
    /// Where there is none of those (no `HOME` or `XDG_CACHE_HOME`), it is a directory of the
    /// process's user inside the temporary directory, one nobody else created or can rename away,
    /// or, if the temporary directory cannot be trusted, a new one that lasts as long as the
    /// process. Other platforms use the temporary directory.
    ///
    ///   `FileSystem.shared.temporaryDirectory` is the NIO one and would otherwise be the obvious
    ///   choice, but it is `async throws` and this call chain cannot suspend: it is reached from
    ///   `public init(...)` and, through those, from `public static let shared = DataCache()`.
    ///   A stored property cannot be initialised from an asynchronous call.
    static func temporaryURL(suiteName: String) -> URL {
        URL(fileURLWithPath: FilePath.cachesDirectory.string, isDirectory: true)
            .appendingPathComponent(
                "com.request-dl-nio.Swift.Cache",
                isDirectory: true
            )
            .appendingPathComponent(
                sanitizedPathComponent(suiteName),
                isDirectory: true
            )
    }

    static func mainTemporaryURL() -> URL {
        temporaryURL(suiteName: ProcessInfo.processInfo.applicationIdentifier)
    }

    // MARK: - Private static methods

    /// Replaces the characters that cannot appear in a single path component.
    ///
    /// - Note: A `map` rather than `replacingOccurrences(of:with:options: .regularExpression)`.
    /// That overload is Foundation's regex path, which is not part of `FoundationEssentials`,
    /// and reaching for a regular expression to rewrite three characters was never a good
    /// trade. `.` is included now: a suite named `..` would otherwise resolve to the parent
    /// directory and put the cache somewhere nobody asked for.
    private static func sanitizedPathComponent(_ name: String) -> String {
        let sanitized = String(
            name.map { character in
                switch character {
                case "/", ":", "\\", ".":
                    return "_"
                default:
                    return character
                }
            }
        )

        return sanitized.isEmpty ? "_" : sanitized
    }

    // MARK: - Public methods

    ///
    /// Retrieves cached data for a specified key and policy.
    ///
    /// - Parameters:
    ///    - key: The key associated with the cached data.
    ///    - policy: The policy indicating the desired behavior for retrieving the cached data.
    /// - Returns: The cached data, if available based on the specified policy.
    ///
    public func getCachedData(forKey key: String, policy: DataCache.Policy.Set) async -> CachedData? {
        let key = base64EncodedKey(key)

        // A write that is not finished is not a response. Its entry is already in the tiers, with
        // what has been written so far (nothing at all, for an encrypted file whose last chunk
        // is sealed on close), and would be served as if it were the whole body.
        guard !storage.isWriting(key: key) else {
            return nil
        }

        if policy.contains(.memory), let cachedData = await storage.memoryStorage[key] {
            storage.withMemoryStorage { $0.markUsed(key) }

            if policy.contains(.disk) {
                storage.diskStorage.markUsed(key)
            }

            return cachedData
        }

        if policy.contains(.disk) {
            guard let cachedData = await storage.diskStorage[key] else {
                return nil
            }

            // The entry came from the disk because memory has not seen it since the process
            // started. Keep it where the next read is cheapest, as long as it was stored for
            // memory too.
            guard policy.contains(.memory), cachedData.policy.contains(.memory) else {
                return cachedData
            }

            return await promotingToMemory(cachedData, forKey: key)
        }

        return nil
        // Memory is consulted first, which is only safe because `allocateBuffer` evicts the
        // memory entry whenever the memory tier refuses the new one. Without that, a response
        // too large for memory but small enough for disk would leave a stale entry in front of
        // a fresh one.
    }

    /// The largest entry read from the disk tier that is kept in memory, as a share of the memory
    /// capacity: one in this many. A larger one would push out many smaller ones for a single
    /// entry, and is the kind that is read as a stream rather than all at once.
    private static let promotionShare: Int64 = 20

    /// Keeps `cachedData`, which came from the disk tier, in the memory tier, and serves it from
    /// there.
    ///
    /// The whole body is read before the entry becomes visible in memory, so a reader never
    /// meets half of it. If the key is written, revalidated or removed meanwhile, the read is
    /// served and thrown away.
    private func promotingToMemory(_ cachedData: CachedData, forKey key: String) async -> CachedData? {
        let size = cachedData.buffer.readableBytes

        guard Int64(size) <= storage.memoryCapacity / Self.promotionShare, storage.beginPromotion(key: key) else {
            return cachedData
        }

        var source = cachedData.buffer
        let bytes = size == .zero ? [] : await source.readBytes(size)

        guard let bytes else {
            storage.cancelPromotion(key: key)

            // What was read is gone from `source`, and a failed read says nothing about the rest.
            return await storage.diskStorage[key]
        }

        let dataURL = Internals.ByteURL()
        dataURL.replace(with: bytes)

        _ = storage.finishPromotion(key: key, cachedResponse: cachedData.cachedResponse, dataURL: dataURL)

        return await CachedData(
            cachedResponse: cachedData.cachedResponse,
            buffer: Internals.DataBuffer(dataURL)
        )
    }

    ///
    /// Sets cached data for a specified key.
    ///
    /// - Parameters:
    ///    - cachedData: The cached data to be stored.
    ///    - key: The key associated with the cached data.
    ///
    public func setCachedData(_ cachedData: CachedData, forKey key: String) async {
        var buffer = await allocateBuffer(
            key: key,
            cachedResponse: cachedData.cachedResponse,
            contentLength: Int64(cachedData.buffer.readableBytes)
        )

        await buffer?.writeBuffer(cachedData.buffer)

        if let buffer {
            await finalizeWrite(buffer, contentLengthHint: Int64(cachedData.buffer.readableBytes))
        }
    }

    ///
    /// Removes cached data for a specified key.
    ///
    /// - Parameter key: The key associated with the cached data to be removed.
    ///
    public func remove(forKey key: String) async {
        let key = base64EncodedKey(key)

        storage.invalidatePromotion(key: key)
        storage.withMemoryStorage { $0.remove(key) }
        await storage.diskStorage.remove(key)
    }

    /// Removes the entry at `key` in each tier that still holds the one that was stored at `date`.
    ///
    /// For whoever found an entry unusable, or stale, some time ago: the entry may have been
    /// renewed (revalidated) or replaced since, and that one is not what it found. A key that is
    /// being written is left alone, since what is there is not the entry either.
    func remove(forKey key: String, ifDated date: Date) async {
        let key = base64EncodedKey(key)

        guard !storage.isWriting(key: key) else {
            return
        }

        if let memory = await storage.memoryStorage[key], memory.cachedResponse.date == date {
            storage.invalidatePromotion(key: key)
            storage.withMemoryStorage { $0.remove(key) }
        }

        if let disk = await storage.diskStorage[key], disk.cachedResponse.date == date {
            storage.invalidatePromotion(key: key)
            await storage.diskStorage.remove(key)
        }
    }

    ///
    /// Removes all cached data from the cache.
    ///
    public func removeAll() async {
        storage.invalidateAllPromotions()
        storage.withMemoryStorage { $0.removeAll() }
        await storage.diskStorage.removeAll()
    }

    ///
    /// Removes all cached data from the cache that was stored on or before a specified date.
    ///
    /// - Parameter date: The cut-off: entries whose response is dated at or before it are removed,
    ///   and later ones are kept. The name is `since` for historical reasons, the comparison
    ///   has always been this one.
    ///
    public func removeAll(since date: Date) async {
        storage.invalidateAllPromotions()
        storage.withMemoryStorage { $0.removeAll(since: date) }
        await storage.diskStorage.removeAll(since: date)
    }

    // MARK: - Internal methods

    /// Replaces the response stored at `key` with `cachedResponse`, keeping its body, in each tier
    /// whose record is still `expected`: the one that was revalidated.
    func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        expecting expected: CachedResponse
    ) async {
        guard !cachedResponse.policy.isEmpty else {
            return
        }

        let key = base64EncodedKey(key)

        storage.invalidatePromotion(key: key)

        // Read before entering the critical section below: the lock is not reentrant, and
        // these getters take it.
        let memoryCapacity = self.memoryCapacity

        if cachedResponse.policy.contains(.memory) {
            storage.withMemoryStorage {
                $0.updateCached(
                    key: key,
                    cachedResponse: cachedResponse,
                    expecting: expected,
                    maximumCapacity: memoryCapacity
                )
            }
        }

        if cachedResponse.policy.contains(.disk) {
            await storage.updateDiskCached(
                key: key,
                cachedResponse: cachedResponse,
                expecting: expected
            )
        }
    }

    /// Rewrites the entry at `key` as `cachedResponse`, the revalidated form of `expected`, and
    /// reads back what is stored.
    ///
    /// Revalidations of one entry run side by side, each with its own 304 and its own date, and
    /// rewriting a disk entry moves its body to a new directory. Run together, one of them reads
    /// the entry while another has the body in transit, and the lookup waits out its retry budget
    /// for a file that is on its way, or finds nothing. They take turns instead, and the ones
    /// that come after the first find the entry already renewed (see
    /// ``CachedResponse/isSameEntry(as:)``), which is all they wanted, and leave it where it is.
    ///
    /// - Returns: The entry, `nil` when what is stored is not (any more) the entry that was
    /// revalidated: it was removed, or replaced by a response of its own, which a revalidation of
    /// something else says nothing about.
    func renewCached(
        key: String,
        cachedResponse: CachedResponse,
        expecting expected: CachedResponse,
        policy: DataCache.Policy.Set
    ) async -> CachedData? {
        await storage.withRevalidationLock(forKey: key) {
            await updateCached(key: key, cachedResponse: cachedResponse, expecting: expected)

            guard
                let updated = await getCachedData(forKey: key, policy: policy),
                updated.cachedResponse.isSameEntry(as: cachedResponse)
            else {
                return nil
            }

            return updated
        }
    }

    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64
    ) async -> Buffer? {
        guard !cachedResponse.policy.isEmpty else {
            return nil
        }

        let key = base64EncodedKey(key)

        // Before anything is installed in a tier: from then on the entry exists, empty.
        let writeToken = storage.beginWrite(key: key)

        var memoryBuffer: Internals.AnyBuffer?
        var memoryDataURL: Internals.ByteURL?
        var replacedMemoryRecord: MemoryStorage.Record?
        var diskBuffer: Internals.AnyBuffer?
        var diskRecordURL: URL?

        if cachedResponse.policy.contains(.memory) {
            // Bookkeeping (reservation, usage-estimate update) happens inside
            // `allocateMemoryDataURL`'s own lock acquisition; opening a buffer over the result is
            // asynchronous and belongs outside it, which also keeps the lock from being held
            // across that.
            let allocated = storage.allocateMemoryDataURL(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength
            )

            memoryDataURL = allocated?.dataURL
            replacedMemoryRecord = allocated?.replaced

            if let memoryDataURL {
                memoryBuffer = await Internals.DataBuffer(memoryDataURL)
            }
        }

        if cachedResponse.policy.contains(.disk) {
            (diskBuffer, diskRecordURL) = await storage.allocateDiskBuffer(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength
            )
        }

        // Nothing was installed (the entry did not fit, or the disk write could not start), so
        // there is no write to wait for.
        if memoryBuffer == nil, diskBuffer == nil {
            writeToken.end()
        }

        // What a tier holds of this write goes when the body outgrows the tier: the exact record
        // this write allocated, by reference, as `discardFailedWrite(_:forKey:)` does.
        let storage = self.storage
        let memoryRecord = memoryDataURL
        let diskRecord = diskRecordURL

        let onOverflow: @Sendable (Buffer.Tier) async -> Void = { tier in
            switch tier {
            case .memory:
                if let memoryRecord {
                    storage.withMemoryStorage { $0.remove(key, ifDataURL: memoryRecord) }
                }
            case .disk:
                if let diskRecord {
                    await storage.diskStorage.removeRecord(at: diskRecord)
                }
            }
        }

        return .init(
            memoryBuffer: memoryBuffer,
            diskBuffer: diskBuffer,
            diskRecordURL: diskRecordURL,
            memoryDataURL: memoryDataURL,
            replacedMemoryRecord: replacedMemoryRecord,
            writeToken: writeToken,
            memoryCapacity: storage.memoryCapacity,
            diskCapacity: storage.diskCapacity,
            onOverflow: onOverflow
        )
    }

    /// Discards a cache write that started via
    /// ``allocateBuffer(key:cachedResponse:contentLength:)`` but never finished (its body stream
    /// was cancelled or errored before writing through `buffer` completed).
    ///
    /// - Important: Not the same as ``remove(forKey:)``. That method finds entries through
    /// `DiskStorage.record(_:)`, which needs both `response.record` and `data.record` on disk,
    /// a gate an unfinished write can't pass, so it would silently leave the half-written
    /// directory behind. This method targets `buffer.diskRecordURL`, the exact directory
    /// captured at allocation, so it deletes precisely the failed write and never an unrelated
    /// in-progress write to the same key. `buffer.memoryDataURL` gives the memory tier the same
    /// precision: `MemoryStorage.remove(_:ifDataURL:)` only removes `key`'s record when it is
    /// still the one this write allocated.
    func discardFailedWrite(_ buffer: Buffer, forKey key: String) async {
        let key = base64EncodedKey(key)

        if let memoryDataURL = buffer.memoryDataURL {
            storage.withMemoryStorage { memory in
                // What this write was going to replace stays, as it does on disk.
                if let replaced = buffer.replacedMemoryRecord {
                    memory.restore(replaced, forKey: key, ifDataURL: memoryDataURL)
                } else {
                    memory.remove(key, ifDataURL: memoryDataURL)
                }
            }
        }

        if let diskRecordURL = buffer.diskRecordURL {
            await storage.diskStorage.removeRecord(at: diskRecordURL)
        }

        buffer.writeToken?.end()
    }

    /// Reconciles each tier's tracked usage estimate with a completed write's real byte count,
    /// once the whole body has been written through `buffer` successfully.
    ///
    /// `allocateBuffer(key:cachedResponse:contentLength:)` estimates a write from the response's
    /// `Content-Length` header, which is `0` when the header is absent (as with chunked transfer
    /// encoding). The bytes actually written aren't bounded by that hint, so without this
    /// correction the tracked estimate can understate real usage by the entire body size. See
    /// `Storage.reconcileMemoryUsage(contentLengthHint:actualSize:)`.
    ///
    /// Not called from ``discardFailedWrite(_:forKey:)``'s path, since a write that never
    /// finished removes its own record outright and has no usage left to have miscounted.
    func finalizeWrite(_ buffer: Buffer, contentLengthHint: Int64) async {
        // Closed here, before the entry can be read: the disk buffer is otherwise closed when it is
        // released, and an encrypted file has no final chunk until then.
        await buffer.closeDiskBuffer()

        defer { buffer.writeToken?.end() }

        // The write is whole now: the record stops being an unfinished one, and the generations
        // of the key before it are no longer needed. A tier the body outgrew has no record left.
        if let diskRecordURL = buffer.diskRecordURL, !buffer.diskOverflowed {
            await storage.diskStorage.finishRecord(at: diskRecordURL)
        }

        let actualSize = Int64(buffer.readableBytes)

        // A tier the body outgrew holds nothing of it, so its usage goes back to what it was
        // before this write, not to the size of a body it did not keep.
        if buffer.memoryDataURL != nil {
            storage.reconcileMemoryUsage(
                contentLengthHint: contentLengthHint,
                actualSize: buffer.memoryOverflowed ? 0 : actualSize
            )
        }

        if buffer.diskRecordURL != nil {
            storage.reconcileDiskUsage(
                contentLengthHint: contentLengthHint,
                actualSize: buffer.diskOverflowed ? 0 : actualSize
            )
        }
    }

    /// Runs a cache write and keeps track of it, so `waitUntilIdle()` can join it later.
    ///
    /// - Parameter priority: The priority of the request the write belongs to. Without it the
    /// write inherits the priority of the caller, which is what a caller that is itself a task
    /// wants; one that runs on an event loop has to pass the priority it captured instead.
    func trackWrite(
        priority: _Concurrency.TaskPriority? = nil,
        _ operation: @escaping @Sendable () async -> Void
    ) {
        storage.pendingWrites.run(priority: priority, operation)
    }

    /// Suspends until every cache write started so far has finished.
    ///
    /// Caching happens after the caller already has its response, so without this there is no
    /// point at which "the request is done" also means "the cache is written".
    func waitUntilIdle() async {
        await storage.pendingWrites.waitUntilIdle()
    }

    // MARK: - Private methods

    /// The longest storage key embedded verbatim in a disk record's directory name.
    ///
    /// That name is `<base36 date>.<key>.cached`: up to 13 + 1 + key + 7 bytes, and a single path
    /// component is capped at 255 bytes (`NAME_MAX`). Longer keys, such as the base64 of a signed
    /// or search URL over roughly 175 bytes, are hashed instead (see `base64EncodedKey(_:)`).
    private static let maximumVerbatimKeyLength = 200

    /// The storage key for `key`: its base64url encoding, or, when that would be too long for a
    /// file name, `sha256.` followed by the hex SHA-256 of `key`. The `.` can never appear in
    /// base64url output, so the two forms cannot collide.
    func base64EncodedKey(_ key: String) -> String {
        let base64 = Data(key.utf8).base64EncodedString()

        // `compactMap` rather than `replacingOccurrences(of:with:)`, which isn't in
        // `FoundationEssentials`.
        let encoded = String(
            base64.compactMap { character -> Character? in
                switch character {
                case "+": return "-"
                case "/": return "_"
                case "=": return nil
                default: return character
                }
            }
        )

        guard encoded.utf8.count > Self.maximumVerbatimKeyLength else {
            return encoded
        }

        let digest = SHA256.hash(data: Data(key.utf8))
        return "sha256."
            + digest.map { byte in
                let hex = String(byte, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }.joined()
    }
}
