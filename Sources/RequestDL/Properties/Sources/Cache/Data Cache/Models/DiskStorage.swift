//
// See LICENSE for this package's licensing information.
//

import Crypto
import Dispatch
import RequestDLInternals
import SwiftAsyncStream
import SystemPackage

#if canImport(NIOCore)
import NIOCore
import NIOFileSystem
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#if canImport(NIOCore)
import NIOFoundationEssentialsCompat
#endif
#else
import struct Foundation.URL
import struct Foundation.Date
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
#endif

#if canImport(Darwin)
import class Foundation.FileManager
import struct Foundation.FileAttributeKey
import struct Foundation.FileProtectionType
#endif

struct DiskStorage: Sendable {

    struct Record: Sendable {

        // MARK: - Internal static properties
        static let pathExtension = "cached"
        private static let responsePath = "response.record"
        private static let dataPath = "data.record"

        // MARK: - Internal properties
        var size: Int64 {
            get async {
                let responsePath = responseURL.filePath
                let dataPath = dataURL.filePath

                let responseInfo = try? await Internals.fileSystem.info(forFileAt: responsePath)
                let dataInfo = try? await Internals.fileSystem.info(forFileAt: dataPath)

                return (responseInfo?.size ?? 0) + (dataInfo?.size ?? 0)
            }
        }

        let key: String
        let url: URL
        let date: Date
        let responseURL: URL
        let dataURL: URL

        // MARK: - Inits

        /// - Parameter retryOnMiss: Whether a missing `response.record`/`data.record` gets the
        /// full retry budget (see `isReachableWithRetry`'s doc comment) before being treated as a
        /// genuine absence.
        ///
        /// `record(forKey:)`'s by-key lookup passes `true` (the default): the record it's
        /// checking was just written and closed right before, so a miss there is the transient
        /// stat flake the retry exists for.
        ///
        /// A directory-wide scan passes `true` for at most the one entry whose key is actually
        /// being looked up, and `false` for every other. A miss on one of those others is just
        /// as likely to mean that entry's write is still in progress, and it is not what the
        /// caller asked about: retrying each of them for up to 15s, serially, would turn
        /// `freeSpace`/`removeAll(since:)`/a single cold lookup into a multi-second stall per
        /// unrelated in-flight write.
        init?(_ url: URL, retryOnMiss: Bool = true) async {
            guard url.pathExtension == Self.pathExtension,
                let (key, date) = Self.getKeyAndDate(url)
            else { return nil }

            let responseURL = url.appendingPathComponent(Self.responsePath)
            let dataURL = url.appendingPathComponent(Self.dataPath)

            // Both files have to be on disk for the record to be usable. Short circuits on the
            // first miss instead of awaiting both: `isReachableWithRetry` can spend its full retry
            // budget (300 attempts, 15s) telling a transient flake from a genuine absence, so
            // awaiting a second one after the first already came back negative would double that
            // worst case.
            func isReachable(_ url: URL) async -> Bool {
                retryOnMiss ? await Self.isReachableWithRetry(url) : await url.isReachable
            }

            guard await isReachable(responseURL) else { return nil }
            guard await isReachable(dataURL) else { return nil }

            self.date = date
            self.key = key
            self.url = url
            self.responseURL = responseURL
            self.dataURL = dataURL
        }

        init(directory: URL, key: String, at date: Date) async {
            // The raw bit pattern of the interval, not a nanosecond count. `updateCached`
            // creates a fresh record for the same key while revalidating an existing one, and
            // two records for the same key landing in the same directory name would otherwise
            // collide; `moveItem` then throws, and the recovery path removes both the old and
            // the new record, losing the entry outright.
            //
            // Scaling `timeIntervalSinceReferenceDate` by 1e9 does not avoid that: the interval
            // is already well past `Double`'s 2^53 exact-integer range by the time this runs in
            // 2026, so the scaled product is itself rounded during the multiply, and
            // reconstructing a `Date` from that rounded value can land a hair off from the
            // original, enough for `record.date <= date` to disagree with the `Date` it was
            // built from. The bit pattern round-trips exactly, with no arithmetic to lose
            // precision on either side.
            let bitPattern = date.timeIntervalSinceReferenceDate.bitPattern
            var directoryPathComponent = String(bitPattern, radix: 36)
            directoryPathComponent += ".\(key).\(DiskStorage.Record.pathExtension)"

            let url = directory.appendingPathComponent(directoryPathComponent, isDirectory: true)
            let responseURL = url.appendingPathComponent(DiskStorage.Record.responsePath)
            let dataURL = url.appendingPathComponent(DiskStorage.Record.dataPath)

            self.url = url
            self.key = key
            self.date = date
            self.responseURL = responseURL
            self.dataURL = dataURL

            do {
                // Owner only, the cache root and the directories above it included: their names
                // are derived from the URL they cache, and the default (readable by everyone)
                // would list those to every other user of the machine.
                try await Internals.fileSystem.createDirectory(
                    at: url.filePath,
                    withIntermediateDirectories: true,
                    permissions: .ownerReadWriteExecute
                )
            } catch {
                // Silent. Whoever writes through this record reports the failure with context.
            }
        }

        // MARK: - Private static methods

        /// Whether `url` exists, retrying past the transient miss `Internals.fileSystem.info`
        /// is already known to produce.
        ///
        /// This is the same flake `Internals.Buffer.Storage._isResourceAvailable()` retries
        /// around: a stat can intermittently come back negative for a file that was just
        /// written and closed, with nothing thrown and no descriptor left open. A record's own
        /// `response.record`/`data.record` are written and closed synchronously right before
        /// this runs, so a miss here is that stat flake, not a genuine absence. Skip the retry
        /// and it turns a rare stat flake into a lost cache entry.
        private static func isReachableWithRetry(_ url: URL) async -> Bool {
            await DiskStorage.retryingUntilSuccess { await url.isReachable ? true : nil } ?? false
        }

        /// The cache key `url`'s directory name encodes, or `nil` if it doesn't name a record
        /// directory at all.
        ///
        /// Purely a string parse with no file system access, so a scan can tell which entry it is
        /// standing on *before* deciding how hard to stat it.
        static func key(at url: URL) -> String? {
            guard url.pathExtension == Self.pathExtension else { return nil }
            return getKeyAndDate(url)?.0
        }

        static func getKeyAndDate(_ url: URL) -> (String, Date)? {
            var components = url.deletingPathExtension().lastPathComponent.split(separator: ".")
            guard let bitPattern = components.first.flatMap({ UInt64($0, radix: 36) }) else { return nil }
            components.removeFirst()
            return (
                components.joined(separator: "."),
                Date(timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern))
            )
        }
    }

    /// A directory-wide, in-process index from cache key to the record directory that holds
    /// it, the fast path `record(forKey:)` uses instead of listing every entry in
    /// `directory` on every lookup.
    ///
    /// A HIT is trusted immediately, with no disk access at all: once a write records a
    /// location for a key, only an explicit, guarded removal ever clears it. A MISS never is.
    ///
    /// `dir.listContents()` racing a burst of very recent creates can come back incomplete, the
    /// same class of transient filesystem flake `Record.init?`'s own retry loop already
    /// tolerates for a single file, just one layer up, at the directory-listing level, where
    /// there is nothing to retry against within one scan. Trusting a first scan's absence
    /// forever would turn that transient gap into a permanent false miss, silently.
    ///
    /// So a miss here re-scans before answering: it shares that scan across concurrent
    /// callers who miss at the same time (e.g. a list of images loading at once, before any of
    /// them is cached yet) rather than each starting their own, and always merges forward
    /// rather than caching a negative result for a key.
    ///
    /// What a miss does not do is scan again while the last scan is still recent. Every scan
    /// costs a directory listing plus two stats per entry, so a miss per scan makes `M` lookups
    /// of keys that are not cached over `N` entries cost `N * M`, which a screenful of new
    /// images over a full cache turns into thousands of stats a second. A miss inside
    /// `minimumRescanInterval` of the last scan answers `nil` straight away. This is safe for
    /// what this instance wrote, since a write publishes its location into the index and never
    /// depends on a scan. The one thing it can miss is an entry another instance or process
    /// wrote after that scan, which becomes visible within the interval, and a cache miss on a
    /// shared directory is a cost, not a wrong answer.
    ///
    /// - Important: This index only tracks writes and removals made through *this* value's
    /// own methods. A location written by a different `DiskStorage`/process sharing the same
    /// directory (e.g. via `suiteName`) is invisible to it until the next scan. That's the same
    /// staleness `Storage._diskUsageEstimate` already tolerates for eviction accounting. A
    /// lookup that misses falls through to a live scan rather than a wrong answer; it never
    /// serves stale *content*, only an occasional avoidable one.
    private final class Index: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        private let minimumRescanInterval: UInt64

        private var locationsByKey: [String: URL] = [:]
        private var lastUsedByKey: [String: Date] = [:]
        private var refreshTask: Task<Void, Never>?
        private var lastScanEnd: UInt64?
        private var _scanCount = 0

        // MARK: - Inits

        /// - Parameter minimumRescanInterval: Seconds a miss waits after the last scan before
        /// it may start another. Zero scans on every miss.
        init(minimumRescanInterval: Double) {
            self.minimumRescanInterval = UInt64(max(0, minimumRescanInterval) * 1_000_000_000)
        }

        // MARK: - Internal properties

        /// Directory scans started so far, exposed for tests.
        var scanCount: Int {
            lock.withLock { _scanCount }
        }

        // MARK: - Internal methods

        /// Looks up `key`, kicking off or joining a rescan first if it isn't already known.
        func location(for key: String, scan: @escaping @Sendable () async -> [Record]) async -> URL? {
            if let hit = lock.withLock({ locationsByKey[key] }) {
                return hit
            }

            let task: Task<Void, Never>? = lock.withLock {
                if let refreshTask {
                    return refreshTask
                }

                // The last scan was a moment ago and did not find `key`: nothing this instance
                // wrote since is missing from the index, so another scan would only repeat it.
                if let lastScanEnd, Self.now() - lastScanEnd < minimumRescanInterval {
                    return nil
                }

                _scanCount += 1

                let newTask = Task {
                    let scanned = await scan()

                    lock.withLock {
                        // Only fills gaps. A write or removal that landed after this scan
                        // started already knows more than a snapshot taken before it did; this
                        // must not overwrite that with stale information.
                        for record in scanned where locationsByKey[record.key] == nil {
                            locationsByKey[record.key] = record.url
                        }

                        refreshTask = nil
                        lastScanEnd = Self.now()
                    }
                }

                refreshTask = newTask
                return newTask
            }

            await task?.value

            return lock.withLock { locationsByKey[key] }
        }

        func set(_ key: String, location url: URL) {
            lock.withLock { locationsByKey[key] = url }
        }

        /// Monotonic, so a clock that moves backwards cannot freeze or skip the window.
        private static func now() -> UInt64 {
            DispatchTime.now().uptimeNanoseconds
        }

        /// Records that `key` was just served, for `freeSpace` to evict it after entries that
        /// were not. Kept for the life of the process only: the order on disk is the creation
        /// order, which is what a freshly launched process starts from.
        func markUsed(_ key: String) {
            lock.withLock {
                if locationsByKey[key] != nil {
                    lastUsedByKey[key] = Date()
                }
            }
        }

        func lastUsed(_ key: String) -> Date? {
            lock.withLock { lastUsedByKey[key] }
        }

        /// Removes the mapping for `key` only if it still points at `url`.
        ///
        /// Guards against a slower removal of a stale or superseded directory clobbering a
        /// newer write that already replaced it in the index. The two can race whenever a
        /// duplicate directory for the same key gets cleaned up after a fresher write already
        /// pointed the index elsewhere.
        func remove(_ key: String, ifLocation url: URL) {
            lock.withLock {
                if locationsByKey[key] == url {
                    locationsByKey[key] = nil
                    lastUsedByKey[key] = nil
                }
            }
        }

        func removeAll() {
            lock.withLock {
                locationsByKey = [:]
                lastUsedByKey = [:]
            }
        }
    }

    // MARK: - Private properties
    private let directory: URL
    private let index: Index

    // MARK: - Internal properties

    /// The Data Protection class newly written cache files are given, on platforms that support
    /// it. `nil` (the default) leaves the system default in place, matching this type's
    /// behavior before this property existed.
    #if canImport(Darwin)
    var fileProtection: FileProtectionType?
    #endif

    /// The key `response.record` and `data.record` are encrypted with, on platforms and disk
    /// tiers this type controls. `nil` (the default) leaves both files in plaintext, matching
    /// this type's behavior before this property existed. Cross-platform, unlike
    /// `fileProtection`: `swift-crypto` needs no OS-specific support.
    var encryptionKey: DataCache.EncryptionKey?

    // MARK: - Inits
    /// - Parameter missRescanInterval: Seconds a cache miss waits after the last directory
    /// scan before it may scan again; see `Index`. Zero scans on every miss.
    init(directory: URL, missRescanInterval: Double = 1) {
        self.directory = directory
        self.index = Index(minimumRescanInterval: missRescanInterval)
    }

    /// Directory scans the lookup index has started, exposed for tests.
    var scanCount: Int {
        index.scanCount
    }

    // MARK: - Internal methods

    subscript(_ key: String) -> CachedData? {
        get async {
            guard let record = await record(key) else { return nil }

            guard let responseData = await readResponseData(at: record.responseURL) else {
                return nil
            }

            guard
                let cachedResponse = try? JSONDecoder().decode(
                    CachedResponse.self,
                    from: responseData
                )
            else { return nil }

            index.markUsed(key)

            return await .init(
                cachedResponse: cachedResponse,
                buffer: dataBuffer(for: record)
            )
        }
    }

    /// Reads a whole file into memory, closing the handle before returning on every path.
    ///
    /// - Note: `NIOFileSystem`'s handles are not closed by `deinit`. Dropping the last
    /// reference to one that is still open is a fatal error, on purpose: a leaked descriptor is
    /// a resource leak that would otherwise stay silent until the process runs out of them.
    ///
    /// `defer` cannot carry the fix here: its body cannot `await`, and the close is a NIO call
    /// that has to be. So the read result is captured first, closed unconditionally right after,
    /// and only then is the outcome inspected. That keeps a single `await handle.close()` on
    /// the path regardless of whether the read succeeded, and closes before the function
    /// returns rather than racing a detached task against it.
    ///
    /// - Important: Must close on every path, not only when `readToEnd` succeeds. A miss on
    /// `openFile` is harmless, since nothing has opened yet. A miss on `readToEnd` is not: if
    /// `try?` swallows the throw and the `guard` chain fails without closing first, the function
    /// returns `nil` with the handle still open and now unreachable. That's exactly the trap NIO
    /// traps on, for a cache entry whose response record simply failed to read.
    ///
    /// - Note: `openFile` is retried (`retryingUntilSuccess`) rather than attempted once: `url`
    /// only gets here after `Record.init?` already confirmed it reachable, so an `openFile` miss
    /// right after is the same transient stat/open flake `isReachableWithRetry` retries around,
    /// not a genuine absence. Skipping the retry would surface that flake all the way up
    /// through this method, and therefore `subscript(_:)`, as `nil` for an entry that was just
    /// written.
    private func readResponseData(at url: URL) async -> Data? {
        guard
            let handle = await Self.retryingUntilSuccess({
                try? await Internals.fileSystem.openFile(forReadingAt: url.filePath)
            })
        else {
            return nil
        }

        let buffer = try? await handle.readToEnd(maximumSizeAllowed: .unlimited)
        try? await Internals.uncancellable { try await handle.close() }

        guard let buffer else {
            return nil
        }

        #if canImport(NIOCore)
        let raw =
            buffer.getData(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            ) ?? Data()
        #else
        let raw = buffer
        #endif

        guard let encryptionKey else {
            return raw
        }

        // Wrong/rotated key, and a corrupted or tampered file, both fail here; `try?` turns
        // either into a miss, matching every other fault-tolerance path in this type.
        guard
            let sealedBox = try? AES.GCM.SealedBox(combined: raw),
            let opened = try? AES.GCM.open(sealedBox, using: encryptionKey.symmetricKey)
        else {
            return nil
        }

        return opened
    }

    /// The buffer `data.record` is read through or written into, plain when no key is
    /// configured, chunk-encrypted otherwise. Both satisfy `Internals.AnyBuffer`, so nothing
    /// above this call site needs to know which one it got.
    ///
    /// - Parameter retryingEmptyContent: Forwarded to `Internals.Buffer.init(addressing:...)`.
    /// A read passes the default `true`, since a zero-byte answer there may be the transient
    /// stat flake that retry exists for. `allocateBuffer` passes `false`: it has just created
    /// the file and knows nothing was written yet, so the retry could only exhaust its whole
    /// budget (~290ms of sleeping before every encrypted cache write).
    private func dataBuffer(
        for record: Record,
        retryingEmptyContent: Bool = true
    ) async -> Internals.AnyBuffer {
        guard let encryptionKey else {
            return await Internals.FileBuffer(record.dataURL)
        }

        let url = Internals.EncryptedFileBufferURL(
            inner: .init(record.dataURL),
            key: encryptionKey.symmetricKey
        )

        return await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(
            addressing: url,
            retryingEmptyContent: retryingEmptyContent
        )
    }

    // MARK: - Private static methods

    /// Retries `operation` past the transient stat/open miss `Internals.fileSystem` is already
    /// known to produce under heavy concurrent disk access on sandboxed Apple simulators: a
    /// check or open can intermittently fail for a file that was just written/confirmed, with
    /// nothing thrown and no descriptor left open. Shared by `Record.isReachableWithRetry` and
    /// `readResponseData`, the two places here that read a `.cached` entry right after its own
    /// existence was (or is about to be) confirmed, where a fresh miss is that flake, not a
    /// genuine absence.
    ///
    /// - Note: 300 attempts, 50ms apart: a 15s budget. CI's Apple simulator runners have been
    /// observed stalling the entire test process for 15-27s under scheduler contention (see the
    /// request-dl-nio CI-flakiness investigation into `AsyncLock.Watchdog` false positives, the
    /// same underlying contention, just surfacing here as a missed stat instead of a held
    /// lock). 15s matches `AsyncLock.Watchdog`'s own threshold for the same reason. The happy
    /// path still returns on the first attempt; this only changes how long a genuinely slow
    /// stat gets before being treated as a real miss.
    private static func retryingUntilSuccess<T>(
        attempts: Int = 300,
        retryDelay: UInt64 = 50_000_000,
        _ operation: () async -> T?
    ) async -> T? {
        for attempt in 0..<attempts {
            if let result = await operation() {
                return result
            }

            if attempt + 1 < attempts {
                retryCounter.increment()
                try? await Task.sleep(nanoseconds: retryDelay)
            }
        }

        return nil
    }

    /// How many times an operation was tried again, over the life of the process. What a test reads
    /// to tell that a lookup spent its retry budget without having to time it, which a runner
    /// that stalls for seconds at a time makes unreliable in either direction.
    static var retryCount: Int {
        retryCounter.value
    }

    private static let retryCounter = RetryCounter()

    private final class RetryCounter: @unchecked Sendable {

        var value: Int {
            lock.withLock { _value }
        }

        func increment() {
            lock.withLock { _value += 1 }
        }

        private let lock = Lock()
        private var _value = 0
    }

    /// Counts a serve from another tier as a use here too, so an entry the memory tier keeps
    /// answering for is not the first one the disk tier drops.
    func markUsed(_ key: String) {
        index.markUsed(key)
    }

    func remove(_ key: String) async {
        guard let record = await record(key) else { return }
        _ = try? await Internals.fileSystem.removeItem(
            at: record.url.filePath
        )
        index.remove(key, ifLocation: record.url)
    }

    func removeAll() async {
        await freeSpace(.zero)
    }

    func removeAll(since date: Date) async {
        let recordsToCheck = await records()
        for record in recordsToCheck where record.date <= date {
            _ = try? await Internals.fileSystem.removeItem(
                at: record.url.filePath
            )
            index.remove(record.key, ifLocation: record.url)
        }
    }

    func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        maximumCapacity: Int64
    ) async {
        guard let record = await record(key),
            let response = try? JSONEncoder().encode(cachedResponse)
        else { return }

        let responseInfo = try? await Internals.fileSystem.info(forFileAt: record.responseURL.filePath)
        let responseLength = responseInfo?.size ?? 0
        let spaceChange = Int64(response.count) - Int64(responseLength)
        let spaceNeeded = Int64(spaceChange < 0 ? 0 : spaceChange)

        guard spaceNeeded <= maximumCapacity else { return }

        await freeSpace(maximumCapacity - spaceNeeded)

        guard await record.dataURL.isReachable,
            let newRecord = await self.record(key, createdAt: cachedResponse.date)
        else { return }

        do {
            let oldDataPath = record.dataURL.filePath
            let newDataPath = newRecord.dataURL.filePath
            try await Internals.fileSystem.moveItem(at: oldDataPath, to: newDataPath)

            try await writeAndClose(response, to: newRecord.responseURL)

            // `newDataPath` carries whatever protection class it already had across the move
            // above: renaming within the same volume does not touch a file's contents or its
            // extended attributes. Only the freshly (re)written response record needs it applied
            // again here.
            #if canImport(Darwin)
            await applyFileProtection(toResponseRecordAt: newRecord.responseURL)
            #endif

            index.set(key, location: newRecord.url)
        } catch {
            _ = try? await Internals.fileSystem.removeItem(
                at: newRecord.url.filePath
            )
            index.remove(key, ifLocation: newRecord.url)
        }

        _ = try? await Internals.fileSystem.removeItem(
            at: record.url.filePath
        )
        // A no-op when the `do` branch above already repointed `key` at `newRecord.url`; clears
        // it when the move failed and there is nothing left on disk for this key at all. See
        // the comment on `Record.init(directory:key:at:)` for why a failed revalidation loses
        // the entry outright rather than leaving `record`'s directory in place.
        index.remove(key, ifLocation: record.url)
    }

    /// - Parameter knownUsage: A caller-tracked estimate of current disk usage, used only to
    /// decide whether `freeSpace` can skip its directory rescan below. See that method's doc
    /// for the safety argument: passing a stale or absent estimate never risks correctness,
    /// only an avoidable rescan.
    /// - Returns: The buffer to write through, disk usage immediately after this write (`nil`
    /// when the write didn't happen, e.g. the entry doesn't fit at all) for the caller to keep
    /// as its next `knownUsage`, and the exact directory this call created on disk (`nil`
    /// exactly when `buffer` is), for the caller to hand back to ``removeRecord(at:)`` if the
    /// write it's about to do through `buffer` ends up never finishing.
    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) async -> (buffer: Internals.AnyBuffer?, usage: Int64?, recordURL: URL?) {
        guard let response = try? JSONEncoder().encode(cachedResponse) else { return (nil, nil, nil) }

        let writableBytes = Int64(response.count) + contentLength
        guard writableBytes <= maximumCapacity else { return (nil, nil, nil) }

        let usageAfterEviction = await freeSpace(
            maximumCapacity - writableBytes,
            knownUsage: knownUsage
        )

        guard let record = await record(key, createdAt: cachedResponse.date) else { return (nil, nil, nil) }

        do {
            try await writeAndClose(response, to: record.responseURL)
        } catch {
            // The directory itself was already created above (`Record.init(directory:key:at:)`
            // creates it unconditionally). Left behind, it would be indistinguishable from the
            // orphan `removeRecord(at:)` exists to clean up elsewhere, except nobody has a
            // reason to call that for a write that never even got a buffer back. Deleting it
            // here, while its exact URL is still in hand, is cheaper and more certain than
            // hoping a later cleanup pass finds it by name.
            await removeRecord(at: record.url)
            return (nil, nil, nil)
        }

        // `data.record` is otherwise created lazily, by the first byte written through the
        // buffer below. A response with an empty body never writes that byte, so the file never
        // appears, and `Record.init?`'s both-files-present gate makes the directory permanently
        // unfindable: invisible to every read and to `remove(_:)`, yet still on disk and still
        // walked by every future directory scan. Creating it up front keeps a legitimately empty
        // response a normal, discoverable, evictable cache entry instead of an orphan.
        try? await record.dataURL.createPathIfNeeded()

        #if canImport(Darwin)
        await applyFileProtection(to: record)
        #endif

        let buffer = await dataBuffer(for: record, retryingEmptyContent: false)
        index.set(key, location: record.url)
        return (buffer, usageAfterEviction + writableBytes, record.url)
    }

    /// Deletes exactly the record directory at `url`, bypassing `record(_:)`'s completeness
    /// gate entirely.
    ///
    /// That gate (both `response.record` and `data.record` present) is correct for every
    /// read path (`subscript`, `updateCached`, eviction), which must never serve or reason
    /// about a write that never finished. But it also means those lookups can never be used to
    /// find and delete such a write's own leftover directory: an entry missing `data.record` is
    /// invisible to them by design.
    ///
    /// This exists for the one caller that already knows exactly which directory to remove
    /// without needing to look it up: the `URL` `allocateBuffer` itself just handed back. So
    /// cleaning up a cancelled or errored cache write never has to go searching for what it
    /// already knows.
    func removeRecord(at url: URL) async {
        _ = try? await Internals.fileSystem.removeItem(at: url.filePath)

        // `allocateBuffer` pointed the index at this directory. Left there, the next read of the
        // key is sent to a directory that is gone and spends its whole retry budget (up to 15s)
        // finding that out, for an answer that is simply "no entry".
        if let (key, _) = Record.getKeyAndDate(url) {
            index.remove(key, ifLocation: url)
        }
    }

    /// Evicts the oldest entries, if any, until usage is at or under `maximumCapacity`.
    ///
    /// - Parameter knownUsage: A caller-tracked usage estimate. When it already fits under
    /// `maximumCapacity`, the directory rescan below (a full `listContents()` plus a
    /// reachability check and a size stat *per existing entry*) is skipped outright, since
    /// nothing would be evicted anyway. That is the difference between a single cache write
    /// costing O(1) versus O(current entry count): the latter turns writing `n` entries into
    /// O(n²) total filesystem operations, cheap enough to hide on a fast local disk but not on
    /// a simulator's slower, host-bridged filesystem, where it has been the underlying cause of
    /// `AsyncLock.Watchdog` firing on otherwise-healthy cache writes.
    ///
    /// Skipping is safe regardless of how accurate `knownUsage` is:
    /// - If it undercounts (e.g. another process sharing this directory, via `suiteName`, wrote
    ///   since it was last reconciled here), the result is a transient, bounded overshoot of
    ///   `maximumCapacity` (never data loss or corruption) that self-corrects the next time
    ///   this runs without a `knownUsage` that still fits, which forces the real rescan below
    ///   and hands back a freshly reconciled total.
    /// - If it overcounts, this just skips straight to an unnecessary-but-harmless rescan.
    ///
    /// A missing `knownUsage` always takes the rescan path.
    ///
    /// - Returns: Usage immediately after this call: either the untouched `knownUsage` when
    /// skipped, or the freshly measured total otherwise, for the caller to reuse as its next
    /// `knownUsage`.
    @discardableResult
    func freeSpace(_ maximumCapacity: Int64, knownUsage: Int64? = nil) async -> Int64 {
        if let knownUsage, knownUsage <= maximumCapacity {
            return knownUsage
        }

        var entries = await records()

        if maximumCapacity == .zero {
            for entry in entries {
                _ = try? await Internals.fileSystem.removeItem(at: entry.url.filePath)
            }
            index.removeAll()
            return .zero
        }

        // Least recently used first. An entry nobody read since this process started is ordered
        // by when it was created.
        entries.sort { lastUsed(of: $0) < lastUsed(of: $1) }

        var totalSize: Int64 = 0
        var entrySizes: [(Record, Int64)] = []
        for entry in entries {
            let size = await entry.size
            totalSize += size
            entrySizes.append((entry, size))
        }

        for (entry, size) in entrySizes {
            if totalSize <= maximumCapacity {
                break
            }
            _ = try? await Internals.fileSystem.removeItem(
                at: entry.url.filePath
            )
            index.remove(entry.key, ifLocation: entry.url)
            totalSize -= size
        }

        return totalSize
    }

    // MARK: - Private methods

    private func lastUsed(of record: Record) -> Date {
        max(index.lastUsed(record.key) ?? record.date, record.date)
    }

    /// Writes `data` to `url`, replacing whatever was there, and closes the handle on every
    /// path, including the one where the write itself throws.
    ///
    /// ## The bug this avoids
    ///
    /// `NIOFileSystem` handles are not closed by `deinit`. Dropping the last reference to one
    /// that is still open is a fatal error, on purpose: a leaked descriptor is a resource leak
    /// that would otherwise stay silent until the process runs out of them.
    ///
    ///   `SystemFileHandle.swift:131: Fatal error: Leaking file descriptor ...`
    ///
    /// - Important: Must not open, write, and close as three statements inside one `do` block:
    ///
    /// ```swift
    /// let handle = try await Internals.fileSystem.openFile(...)
    /// try await handle.write(contentsOf: response, toAbsoluteOffset: .zero)
    /// try await handle.close()
    /// ```
    ///
    /// A throw from `write` (a full disk, a permission error, anything) jumps straight to
    /// `catch`, and `close()` never runs. The handle is still open, and it is also now
    /// unreachable, which is exactly what NIO traps on. `readResponseData(at:)` a few lines up
    /// closes on every path for the read side; this method gives the write side the same
    /// discipline.
    ///
    /// - Throws: Whatever the open or the write threw. The close error is deliberately not
    /// propagated: reporting a failure to close over a failure to write would point at the
    /// wrong half of the problem, and the two call sites already have their own recovery for a
    /// write that failed.
    /// Guards the `combined` unwrap in `writeAndClose` below, reachable only if a future change
    /// starts passing an explicit non-default nonce to `AES.GCM.seal`, which `.combined` cannot
    /// represent. Never expected to actually throw today.
    private struct SealFailureError: Error {}

    private func writeAndClose(_ data: Data, to url: URL) async throws {
        let payload: Data

        if let encryptionKey {
            // `.combined` bundles a fresh random nonce with the ciphertext and tag in one blob,
            // self-describing, no extra framing needed for a file this small (`response.record`
            // is metadata/headers, never the response body). `nil` only when a non-default
            // nonce size was used, which never happens here (no explicit nonce is passed). It's
            // guarded rather than force-unwrapped so a future change can't silently start
            // writing plaintext under this branch; it throws instead, same as any other write
            // failure.
            guard let combined = try AES.GCM.seal(data, using: encryptionKey.symmetricKey).combined else {
                throw SealFailureError()
            }
            payload = combined
        } else {
            payload = data
        }

        let handle = try await Internals.fileSystem.openFile(
            forWritingAt: url.filePath,
            options: .newFile(replaceExisting: true, permissions: .ownerReadWrite)
        )

        do {
            try await handle.write(contentsOf: payload, toAbsoluteOffset: .zero)
            try await Internals.uncancellable { try await handle.close() }
        } catch {
            try? await Internals.uncancellable { try await handle.close() }
            throw error
        }
    }

    #if canImport(Darwin)
    /// Applies `fileProtection` to a freshly written record's `response.record` and its
    /// still-empty `data.record`.
    ///
    /// - Note: `data.record` holds no bytes yet at this point: `allocateBuffer` creates it empty
    /// and `Internals.FileBuffer` streams into it afterwards, at a moment this type doesn't
    /// control, so the class can't be applied retroactively. Setting it on the empty file here
    /// means the later open (`.modifyFile(createIfNecessary: true, ...)`) finds it already there,
    /// with the same outcome as creating the whole file with the class.
    private func applyFileProtection(to record: Record) async {
        guard let fileProtection else { return }

        #if targetEnvironment(simulator)
        // Every Apple Simulator backs its file system with the host Mac's plain APFS volume,
        // not the per-class, hardware-derived encryption real devices use. A protection class
        // set here has no effect and does not even round-trip back through
        // `FileManager.attributesOfItem`. Skipping outright avoids paying for syscalls that can
        // never do anything, on the same shared thread pool every other blocking file op in
        // `Internals` already contends for. `data.record` keeps whatever class the volume gives
        // it by default, exactly as it would with `fileProtection` unset.
        return
        #else
        let responsePath = record.responseURL.path
        let dataPath = record.dataURL.path

        try? await Internals.FileSystemManager.run {
            let attributes: [FileAttributeKey: Any] = [.protectionKey: fileProtection]

            try? FileManager.default.setAttributes(attributes, ofItemAtPath: responsePath)
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: dataPath)
        }
        #endif
    }

    /// Applies `fileProtection` to a `response.record` that already exists on disk: the
    /// revalidation rewrite in `updateCached`, where (unlike `allocateBuffer`) there is no
    /// `data.record` left to pre-create, since it was moved forward from the old record as-is,
    /// class and all.
    private func applyFileProtection(toResponseRecordAt url: URL) async {
        guard let fileProtection else { return }

        #if targetEnvironment(simulator)
        // See the identical guard in `applyFileProtection(to:)` above: a protection class has
        // no effect, and does not even round-trip back through `FileManager.attributesOfItem`,
        // in any Apple Simulator.
        return
        #else
        let path = url.path

        try? await Internals.FileSystemManager.run {
            try? FileManager.default.setAttributes([.protectionKey: fileProtection], ofItemAtPath: path)
        }
        #endif
    }
    #endif

    private func record(_ key: String, createdAt date: Date? = nil) async -> Record? {
        switch date {
        case .none:
            return await record(forKey: key)
        case .some(let date):
            return await Record(directory: directory, key: key, at: date)
        }
    }

    /// Finds the existing record for `key` through `index`, one targeted stat pair instead
    /// of a full directory scan. See `Index`'s doc for what keeps this in sync with writes and
    /// removals, and what it deliberately doesn't cover.
    private func record(forKey key: String) async -> Record? {
        // `retryOnMiss: false`: this scan only decides *which directory* holds `key`, and the
        // record it finds is re-opened with the full retry budget right below. Every entry it walks
        // past belongs to another key, and paying up to 15s per incomplete one, serially, would
        // turn one cold miss into a multi-second stall. A write made through this same instance
        // never needs the scan: `allocateBuffer`/`updateCached` publish their location into `index`
        // directly, so that entry is already a hit above.
        guard let url = await index.location(for: key, scan: { await self.records(retryOnMissFor: key) })
        else {
            return nil
        }

        guard let record = await Record(url) else {
            // The directory the index pointed to turned out to be gone or unreadable: stale, so
            // drop it. Guarded so a newer write that already replaced this mapping isn't
            // clobbered by a check that started against the old one.
            index.remove(key, ifLocation: url)
            return nil
        }

        return record
    }

    /// The full, live directory scan `index` exists to keep off the read path.
    ///
    /// Still the source of truth for anything that has to see every entry regardless of what
    /// `index` knows: `freeSpace`'s eviction accounting and `removeAll(since:)` call this
    /// directly, so a duplicate directory from a lost write race (two concurrent writers for
    /// the same key) stays visible and gets swept up like any other entry.
    ///
    /// - Parameter targetKey: The single key, if any, whose entry is worth the full
    /// `Record.init?(_:retryOnMiss:)` retry budget. `record(forKey:)`'s cold-start scan passes
    /// the key it is looking up, since that entry may have been written moments ago and missing
    /// it would turn a transient stat flake into a false cache miss. A miss on any other entry
    /// is as likely a write still in progress, and paying 15s for each, serially, would turn
    /// one cold lookup into a multi-second stall. `freeSpace`/`removeAll(since:)` pass nothing,
    /// since a bulk sweep has no target key.
    private func records(retryOnMissFor targetKey: String? = nil) async -> [Record] {
        let dirPath = directory.filePath
        var foundRecords: [Record] = []

        do {
            try await Internals.fileSystem.withDirectoryHandle(atPath: dirPath) { dir in
                for try await entry in dir.listContents() {
                    if entry.name.string.hasSuffix(".\(Record.pathExtension)") {
                        let entryURL = directory.appendingPathComponent(entry.name.string)
                        let retryOnMiss = targetKey != nil && Record.key(at: entryURL) == targetKey

                        if let record = await Record(entryURL, retryOnMiss: retryOnMiss) {
                            foundRecords.append(record)
                        }
                    }
                }
            }
        } catch {}

        return foundRecords
    }
}
