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

    private final class Storage: @unchecked Sendable {

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
        let pendingWrites = Internals.PendingTasks(priority: .background)

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

                pendingWrites.run {
                    await diskStorage.freeSpace(newValue)
                }
            }
        }

        // MARK: - Private properties

        private let lock = Lock()

        fileprivate let directory: URL

        // MARK: - Unsafe properties

        // Plain storage. Eviction cannot hang off `didSet` here: one of the two storages is
        // asynchronous, and an observer cannot await. It lives in the setters above instead,
        // in the one place that assigns these — which also keeps the pair symmetrical and makes
        // it visible that shrinking is the only direction that evicts.
        private var _memoryCapacity: Int64
        private var _diskCapacity: Int64

        private var _memoryStorage: MemoryStorage
        private var _diskStorage: DiskStorage

        /// Best-effort disk usage estimate, `nil` until first reconciled. Purely a hint for
        /// `DiskStorage.freeSpace(_:knownUsage:)` to skip its directory rescan on the common
        /// write that isn't anywhere near capacity — never relied on for correctness, so a
        /// stale or absent value only costs an extra rescan, not a wrong eviction. Deliberately
        /// left untouched by `remove`/`removeAll`/capacity changes: those only ever move usage
        /// down or reset it, so an estimate that predates them is at worst a harmless
        /// overcount that triggers one avoidable rescan next time. See #271.
        private var _diskUsageEstimate: Int64?

        /// Same role as `_diskUsageEstimate`, for `MemoryStorage.freeSpace(_:knownUsage:)`. See
        /// that method's doc for the safety argument.
        private var _memoryUsageEstimate: Int64?

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
        ) -> Internals.ByteURL? {
            lock.withLock {
                let (dataURL, usage) = _memoryStorage.allocateBuffer(
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
                return dataURL
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

        /// Corrects `_memoryUsageEstimate` after a write finishes, replacing the `contentLength`
        /// hint `allocateMemoryDataURL` folded in at allocation time with the delta between that
        /// hint and the buffer's real byte count.
        ///
        /// The hint is `0` for any response with no accurate `Content-Length` (chunked transfer
        /// is the common case, since the two are mutually exclusive per HTTP semantics), while
        /// the actual write can be arbitrarily larger. Left unreconciled, the estimate would
        /// permanently undercount such a write, and `MemoryStorage.freeSpace`'s `knownUsage`
        /// short-circuit (see #271/#361) would keep trusting that undercount forever, letting the
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
    /// `nil`, the default, leaves the system default protection class in place — the same
    /// behavior as before this property existed. Setting it only affects cache entries written
    /// from that point on; existing files on disk keep whatever class they already had.
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
    /// `nil`, the default, leaves the disk tier unencrypted — the same behavior as before this
    /// property existed. Setting it only affects cache entries written from that point on;
    /// existing plaintext files on disk are left alone. Supplying a new key does not invalidate
    /// entries written under a previous one: they simply fail to decrypt and are treated as
    /// misses, re-encrypting under the current key the next time they're written. See
    /// ``removeAll()`` for clearing the cache outright, e.g. after a suspected key compromise.
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

    private let storage: Storage
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
    /// which is only cleared between launches, and falls back to the temporary directory on
    /// platforms with no equivalent standard location.
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

        if policy.contains(.memory), let cachedData = await storage.memoryStorage[key] {
            return cachedData
        }

        if policy.contains(.disk) {
            return await storage.diskStorage[key]
        }

        return nil
        // Memory is consulted first, which is only safe because `allocateBuffer` evicts the
        // memory entry whenever the memory tier refuses the new one. Without that, a response
        // too large for memory but small enough for disk would leave a stale entry in front of
        // a fresh one.
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
    }

    ///
    /// Removes cached data for a specified key.
    ///
    /// - Parameter key: The key associated with the cached data to be removed.
    ///
    public func remove(forKey key: String) async {
        let key = base64EncodedKey(key)

        storage.withMemoryStorage { $0.remove(key) }
        await storage.diskStorage.remove(key)
    }

    ///
    /// Removes all cached data from the cache.
    ///
    public func removeAll() async {
        storage.withMemoryStorage { $0.removeAll() }
        await storage.diskStorage.removeAll()
    }

    ///
    /// Removes all cached data from the cache that was stored since a specified date.
    ///
    /// - Parameter date: The date to filter cached data removal.
    ///
    public func removeAll(since date: Date) async {
        storage.withMemoryStorage { $0.removeAll(since: date) }
        await storage.diskStorage.removeAll(since: date)
    }

    // MARK: - Internal methods

    func updateCached(
        key: String,
        cachedResponse: CachedResponse
    ) async {
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
            await storage.diskStorage.updateCached(
                key: key,
                cachedResponse: cachedResponse,
                maximumCapacity: diskCapacity
            )
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

        var memoryBuffer: Internals.AnyBuffer?
        var memoryDataURL: Internals.ByteURL?
        var diskBuffer: Internals.AnyBuffer?
        var diskRecordURL: URL?

        if cachedResponse.policy.contains(.memory) {
            // Bookkeeping (reservation, usage-estimate update) happens inside
            // `allocateMemoryDataURL`'s own lock acquisition; opening a buffer over the result is
            // asynchronous and belongs outside it, which also keeps the lock from being held
            // across that.
            memoryDataURL = storage.allocateMemoryDataURL(
                key: key,
                cachedResponse: cachedResponse,
                contentLength: contentLength
            )

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

        return .init(
            memoryBuffer: memoryBuffer,
            diskBuffer: diskBuffer,
            diskRecordURL: diskRecordURL,
            memoryDataURL: memoryDataURL
        )
    }

    /// Discards a cache write that started via ``allocateBuffer(key:cachedResponse:contentLength:)``
    /// but never finished — its body stream was cancelled, errored, or otherwise gave up before
    /// writing through `buffer` completed.
    ///
    /// - Important: Not the same thing as ``remove(forKey:)``. That method looks entries up by
    /// key through `DiskStorage.record(_:)`, which requires a disk entry's `response.record`
    /// *and* `data.record` to already both be on disk before it can even be found — exactly the
    /// gate a write that never finished can't pass. Called there, it would silently do nothing,
    /// leaving the half-written directory behind: invisible to every future read for the same
    /// reason, yet still costing each of them a multi-second retry budget for `data.record`
    /// permanently missing. This method instead targets `buffer.diskRecordURL` — the exact
    /// directory captured at allocation time — so it finds and deletes precisely the write that
    /// failed, without searching by key and risking an unrelated, still in-progress write to the
    /// same key from a concurrent request. `buffer.memoryDataURL` gives the memory tier the same
    /// precision: `MemoryStorage.remove(_:ifDataURL:)` only removes `key`'s record when it is
    /// still the exact one this write allocated, so a concurrent write to the same key that has
    /// since installed its own (good, current) record is left alone instead of being deleted out
    /// from under it.
    func discardFailedWrite(_ buffer: Buffer, forKey key: String) async {
        let key = base64EncodedKey(key)

        if let memoryDataURL = buffer.memoryDataURL {
            storage.withMemoryStorage { $0.remove(key, ifDataURL: memoryDataURL) }
        }

        if let diskRecordURL = buffer.diskRecordURL {
            await storage.diskStorage.removeRecord(at: diskRecordURL)
        }
    }

    /// Reconciles each tier's tracked usage estimate with a completed write's real byte count,
    /// once the whole body has been written through `buffer` successfully.
    ///
    /// `allocateBuffer(key:cachedResponse:contentLength:)` admits and estimates a write using
    /// `contentLength` as a hint, taken from the response's `Content-Length` header — `0` when
    /// that header is absent, which is exactly the case for chunked transfer encoding. The bytes
    /// actually written via `buffer.writeBuffer` are not bounded by that hint, so for any
    /// response without an accurate `Content-Length`, the tracked estimate can end up
    /// permanently understating real usage by the entire body size unless corrected here. See
    /// `Storage.reconcileMemoryUsage(contentLengthHint:actualSize:)` for why that matters.
    ///
    /// Not called from ``discardFailedWrite(_:forKey:)``'s path: a write that never finished
    /// removes its own record outright, so there is no usage left for it to have miscounted.
    func finalizeWrite(_ buffer: Buffer, contentLengthHint: Int64) {
        let actualSize = Int64(buffer.readableBytes)

        if buffer.memoryDataURL != nil {
            storage.reconcileMemoryUsage(contentLengthHint: contentLengthHint, actualSize: actualSize)
        }

        if buffer.diskRecordURL != nil {
            storage.reconcileDiskUsage(contentLengthHint: contentLengthHint, actualSize: actualSize)
        }
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

    /// - Note: A `compactMap` rather than `replacingOccurrences(of:with:)`, which is not part of
    /// `FoundationEssentials`. Base64's alphabet makes each of these substitutions a single
    /// character, so a character-by-character rewrite covers the same ground.
    /// The longest storage key embedded verbatim in a disk record's directory name.
    ///
    /// That name is `<base36 date>.<key>.cached`: up to 13 + 1 + key + 7 bytes, and a single path
    /// component is capped at 255 bytes (`NAME_MAX`). Past this, the directory could not be
    /// created at all, so a URL longer than roughly 175 bytes (base64 inflates by a third) —
    /// routine for signed or search URLs — was never cached on disk.
    private static let maximumVerbatimKeyLength = 200

    /// The storage key for `key`: its base64url encoding, or, when that would be too long for a
    /// file name, `sha256.` followed by the hex SHA-256 of `key`. The `.` can never appear in
    /// base64url output, so the two forms cannot collide, and short keys keep exactly the
    /// names they always had.
    private func base64EncodedKey(_ key: String) -> String {
        let base64 = Data(key.utf8).base64EncodedString()

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
