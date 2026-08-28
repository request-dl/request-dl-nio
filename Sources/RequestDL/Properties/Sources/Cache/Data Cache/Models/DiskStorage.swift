//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOFileSystem
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
import NIOFoundationEssentialsCompat
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

        init?(_ url: URL) async {
            guard url.pathExtension == Self.pathExtension,
                let (key, date) = Self.getKeyAndDate(url)
            else { return nil }

            let responseURL = url.appendingPathComponent(Self.responsePath)
            let dataURL = url.appendingPathComponent(Self.dataPath)

            // Both files have to be on disk for the record to be usable.
            let responseExists = await Self.isReachableWithRetry(responseURL)
            let dataExists = await Self.isReachableWithRetry(dataURL)

            guard responseExists, dataExists else { return nil }

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
            // the new record, losing the entry outright. Scaling `timeIntervalSinceReferenceDate`
            // by 1e9 does not avoid that: the interval is already well past `Double`'s 2^53
            // exact-integer range by the time this runs in 2026, so the scaled product is itself
            // rounded during the multiply, and reconstructing a `Date` from that rounded value
            // can land a hair off from the original — enough for `record.date <= date` to
            // disagree with the `Date` it was built from. The bit pattern round-trips exactly,
            // with no arithmetic to lose precision on either side.
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
                try await Internals.fileSystem.createDirectory(
                    at: url.filePath,
                    withIntermediateDirectories: true
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
        /// this runs, so a miss here is that stat flake, not a genuine absence — a single
        /// unretried check turned a rare stat flake into a lost cache entry.
        private static func isReachableWithRetry(_ url: URL) async -> Bool {
            await DiskStorage.retryingUntilSuccess { await url.isReachable ? true : nil } ?? false
        }

        private static func getKeyAndDate(_ url: URL) -> (String, Date)? {
            var components = url.deletingPathExtension().lastPathComponent.split(separator: ".")
            guard let bitPattern = components.first.flatMap({ UInt64($0, radix: 36) }) else { return nil }
            components.removeFirst()
            return (
                components.joined(separator: "."),
                Date(timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern))
            )
        }
    }

    // MARK: - Private properties
    private let directory: URL

    // MARK: - Internal properties

    /// The Data Protection class newly written cache files are given, on platforms that support
    /// it. `nil` (the default) leaves the system default in place, matching this type's
    /// behavior before this property existed.
    #if canImport(Darwin)
    var fileProtection: FileProtectionType?
    #endif

    // MARK: - Inits
    init(directory: URL) {
        self.directory = directory
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

            return await .init(
                cachedResponse: cachedResponse,
                buffer: Internals.FileBuffer(record.dataURL)
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
    /// `openFile` is harmless, since nothing has opened yet, but a miss on `readToEnd` is not: if
    /// `try?` swallows the throw and the `guard` chain fails without closing first, the function
    /// returns `nil` with the handle still open and now unreachable — exactly the trap NIO
    /// traps on, for a cache entry whose response record failed to read for any reason.
    ///
    /// - Note: `openFile` is retried (`retryingUntilSuccess`) rather than attempted once: `url`
    /// only gets here after `Record.init?` already confirmed it reachable, so an `openFile` miss
    /// right after is the same transient stat/open flake `isReachableWithRetry` retries around,
    /// not a genuine absence. Before this retry, that flake surfaced as this whole method — and
    /// therefore `subscript(_:)` — returning `nil` for an entry that was just written.
    private func readResponseData(at url: URL) async -> Data? {
        guard
            let handle = await Self.retryingUntilSuccess({
                try? await Internals.fileSystem.openFile(forReadingAt: url.filePath)
            })
        else {
            return nil
        }

        let buffer = try? await handle.readToEnd(maximumSizeAllowed: .unlimited)
        try? await handle.close()

        guard let buffer else {
            return nil
        }

        return buffer.getData(
            at: buffer.readerIndex,
            length: buffer.readableBytes
        ) ?? Data()
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
    /// - Note: 300 attempts, 50ms apart — a 15s budget. The 500ms budget before this (50×10ms,
    /// itself already raised once from an original 5×2ms sized for a quiet machine) still
    /// wasn't enough to keep
    /// `diskStorage_whenFreeingSpaceBelowTotalUsage_shouldEvictOnlyTheOldestEntries` from
    /// flaking: CI's Apple simulator runners have been observed stalling the entire test
    /// process for 15-27s under scheduler contention (see the request-dl-nio CI-flakiness
    /// investigation into `AsyncLock.Watchdog` false positives — the same underlying
    /// contention, just surfacing here as a missed stat instead of a held lock), which a
    /// 500ms budget cannot outlast no matter how the delay is split up. 15s matches
    /// `AsyncLock.Watchdog`'s own threshold for the same reason. The happy path still returns
    /// on the first attempt; this only changes how long a genuinely slow stat gets before being
    /// treated as a real miss.
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
                try? await Task.sleep(nanoseconds: retryDelay)
            }
        }

        return nil
    }

    func remove(_ key: String) async {
        guard let record = await record(key) else { return }
        _ = try? await Internals.fileSystem.removeItem(
            at: record.url.filePath
        )
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
            // above — renaming within the same volume does not touch a file's contents or its
            // extended attributes. Only the freshly (re)written response record needs it applied
            // again here.
            #if canImport(Darwin)
            await applyFileProtection(toResponseRecordAt: newRecord.responseURL)
            #endif
        } catch {
            _ = try? await Internals.fileSystem.removeItem(
                at: newRecord.url.filePath
            )
        }

        _ = try? await Internals.fileSystem.removeItem(
            at: record.url.filePath
        )
    }

    /// - Parameter knownUsage: A caller-tracked estimate of current disk usage, used only to
    /// decide whether `freeSpace` can skip its directory rescan below. See that method's doc
    /// for the safety argument — passing a stale or absent estimate never risks correctness,
    /// only an avoidable rescan.
    /// - Returns: The buffer to write through, and disk usage immediately after this write
    /// (`nil` when the write didn't happen, e.g. the entry doesn't fit at all), for the caller
    /// to keep as its next `knownUsage`.
    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) async -> (buffer: Internals.AnyBuffer?, usage: Int64?) {
        guard let response = try? JSONEncoder().encode(cachedResponse) else { return (nil, nil) }

        let writableBytes = Int64(response.count) + contentLength
        guard writableBytes <= maximumCapacity else { return (nil, nil) }

        let usageAfterEviction = await freeSpace(
            maximumCapacity - writableBytes,
            knownUsage: knownUsage
        )

        guard let record = await record(key, createdAt: cachedResponse.date) else { return (nil, nil) }

        do {
            try await writeAndClose(response, to: record.responseURL)
        } catch {
            return (nil, nil)
        }

        #if canImport(Darwin)
        await applyFileProtection(to: record)
        #endif

        let buffer = await Internals.FileBuffer(record.dataURL)
        return (buffer, usageAfterEviction + writableBytes)
    }

    /// Evicts the oldest entries, if any, until usage is at or under `maximumCapacity`.
    ///
    /// - Parameter knownUsage: A caller-tracked usage estimate. When it already fits under
    /// `maximumCapacity`, the directory rescan below — a full `listContents()` plus a
    /// reachability check and a size stat *per existing entry* — is skipped outright, since
    /// nothing would be evicted anyway. This is the difference between a single cache write
    /// costing O(1) versus O(current entry count): the latter turns writing `n` entries into
    /// O(n²) total filesystem operations, cheap enough to hide on a fast local disk but not on
    /// a simulator's slower, host-bridged filesystem, where it has been the underlying cause of
    /// `AsyncLock.Watchdog` firing on otherwise-healthy cache writes (see #271).
    ///
    /// Skipping is safe regardless of how accurate `knownUsage` is:
    /// - If it undercounts (e.g. another process sharing this directory, via `suiteName`, wrote
    ///   since it was last reconciled here), the result is a transient, bounded overshoot of
    ///   `maximumCapacity` — never data loss or corruption — that self-corrects the next time
    ///   this runs without a `knownUsage` that still fits, which forces the real rescan below
    ///   and hands back a freshly reconciled total.
    /// - If it overcounts, this just skips straight to an unnecessary-but-harmless rescan.
    ///
    /// A missing `knownUsage` always takes the rescan path, so a first call with no estimate
    /// yet, or one that no longer fits, behaves exactly as before this parameter existed.
    ///
    /// - Returns: Usage immediately after this call — either the untouched `knownUsage` when
    /// skipped, or the freshly measured total otherwise — for the caller to reuse as its next
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
            return .zero
        }

        entries.sort { $0.date < $1.date }

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
            totalSize -= size
        }

        return totalSize
    }

    // MARK: - Private methods

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
    /// A throw from `write` — a full disk, a permission error, anything — jumps straight to
    /// `catch`, and `close()` never runs. The handle is still open, and it is also now
    /// unreachable, which is exactly what NIO traps on. `readResponseData(at:)` a few lines up
    /// closes on every path for the read side; this method gives the write side the same
    /// discipline.
    ///
    /// - Throws: Whatever the open or the write threw. The close error is deliberately not
    /// propagated: reporting a failure to close over a failure to write would point at the
    /// wrong half of the problem, and the two call sites already have their own recovery for a
    /// write that failed.
    private func writeAndClose(_ data: Data, to url: URL) async throws {
        let handle = try await Internals.fileSystem.openFile(
            forWritingAt: url.filePath,
            options: .newFile(replaceExisting: true)
        )

        do {
            try await handle.write(contentsOf: data, toAbsoluteOffset: .zero)
            try await handle.close()
        } catch {
            try? await handle.close()
            throw error
        }
    }

    #if canImport(Darwin)
    /// Applies `fileProtection` to a freshly written record's `response.record`, and
    /// pre-creates its `data.record` under the same class before anything is streamed into it.
    ///
    /// - Note: `data.record` does not exist yet at this point — `Internals.FileBuffer` opens it
    /// lazily, on the first byte written through it, which can happen an arbitrary amount of
    /// time after this call returns and has no single moment this type controls to apply the
    /// class retroactively. Pre-creating an empty file here, with the class already set, means
    /// the later lazy open (`.modifyFile(createIfNecessary: true, ...)`) just finds it already
    /// there and writes into it — the same outcome as if the whole file had been created with
    /// the class from the start.
    private func applyFileProtection(to record: Record) async {
        guard let fileProtection else { return }

        #if targetEnvironment(simulator)
        // Every Apple Simulator backs its file system with the host Mac's plain APFS volume,
        // not the per-class, hardware-derived encryption real devices use — a protection class
        // set here has no effect and does not even round-trip back through
        // `FileManager.attributesOfItem`. Skipping outright avoids paying for syscalls that can
        // never do anything, on the same shared thread pool every other blocking file op in
        // `Internals` already contends for. `data.record` is left for `Internals.FileBuffer` to
        // create lazily, exactly as it would with `fileProtection` unset.
        return
        #else
        let responsePath = record.responseURL.path
        let dataPath = record.dataURL.path

        try? await Internals.FileSystemManager.run {
            let attributes: [FileAttributeKey: Any] = [.protectionKey: fileProtection]

            try? FileManager.default.setAttributes(attributes, ofItemAtPath: responsePath)

            if !FileManager.default.fileExists(atPath: dataPath) {
                FileManager.default.createFile(atPath: dataPath, contents: nil, attributes: attributes)
            }
        }
        #endif
    }

    /// Applies `fileProtection` to a `response.record` that already exists on disk — the
    /// revalidation rewrite in `updateCached`, where (unlike `allocateBuffer`) there is no
    /// `data.record` left to pre-create: it was moved forward from the old record as-is, class
    /// and all.
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
            let allRecords = await records()
            return allRecords.first { $0.key == key }
        case .some(let date):
            return await Record(directory: directory, key: key, at: date)
        }
    }

    private func records() async -> [Record] {
        let dirPath = directory.filePath
        var foundRecords: [Record] = []

        do {
            try await Internals.fileSystem.withDirectoryHandle(atPath: dirPath) { dir in
                for try await entry in dir.listContents() {
                    if entry.name.string.hasSuffix(".\(Record.pathExtension)") {
                        let entryURL = directory.appendingPathComponent(entry.name.string)

                        if let record = await Record(entryURL) {
                            foundRecords.append(record)
                        }
                    }
                }
            }
        } catch {}

        return foundRecords
    }
}
