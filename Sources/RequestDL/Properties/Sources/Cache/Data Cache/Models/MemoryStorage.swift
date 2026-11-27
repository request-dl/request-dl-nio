//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.URL
#endif

struct MemoryStorage: Sendable {

    struct Record: Sendable, Hashable {

        // MARK: - Internal properties

        var size: Int64 {
            Int64(dataURL.writtenBytes)
        }

        let key: String
        let date: Date

        /// When this record was last read or written, which is what `freeSpace` orders by.
        var lastUsed: Date

        let cachedResponse: CachedResponse
        var dataURL: Internals.ByteURL

        /// Whether the whole body is in `dataURL`. A record that a write allocated is not, until
        /// that write is finished (see ``MemoryStorage/finish(_:ifDataURL:)``); one that was
        /// installed with its bytes already in place, or renewed from a finished one, is.
        ///
        /// Only a finished record is worth putting back when the write that replaced it is given
        /// up on: an unfinished one is a body that may stop anywhere, and that nobody is left to
        /// complete.
        var isFinished = false

        // MARK: - Inits

        init(
            key: String,
            cachedResponse: CachedResponse
        ) {
            self.key = key
            self.date = cachedResponse.date
            self.lastUsed = Date()
            self.cachedResponse = cachedResponse
            self.dataURL = .init()
        }
    }

    // MARK: - Private properties

    private let directory: URL
    private var records = [String: Record]()

    // MARK: - Inits

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Internal methods

    subscript(_ key: String) -> CachedData? {
        get async {
            guard let record = records[key] else {
                return nil
            }

            return await .init(
                cachedResponse: record.cachedResponse,
                buffer: Internals.DataBuffer(record.dataURL)
            )
        }
    }

    func contains(_ key: String) -> Bool {
        records[key] != nil
    }

    mutating func remove(_ key: String) {
        records[key] = nil
    }

    /// Records that `key` was just served, so `freeSpace` evicts it after entries that were not.
    mutating func markUsed(_ key: String) {
        records[key]?.lastUsed = Date()
    }

    /// Removes `key` only if its currently stored record is still the exact one `dataURL`
    /// identifies, mirroring `DiskStorage.Index.remove(_:ifLocation:)`.
    ///
    /// A plain `remove(_:)` would delete whatever record sits at `key`, even one a concurrent,
    /// still-in-progress write for the same key installed after this caller's write started.
    /// `ByteURL` is a class, so its identity (not its bytes) lets the caller prove it owns the
    /// record it wants to discard.
    mutating func remove(_ key: String, ifDataURL dataURL: Internals.ByteURL) {
        guard records[key]?.dataURL === dataURL else {
            return
        }

        records[key] = nil
    }

    mutating func removeAll() {
        records = [:]
    }

    mutating func removeAll(since date: Date) {
        for (key, entry) in records where entry.date <= date {
            records[key] = nil
        }
    }

    /// Replaces the response a record stores, keeping its body, but only when the record is still
    /// the one `expected` describes.
    ///
    /// A revalidation spans a round trip to the server, and in that time the key can be written
    /// again by a request that did not match what was stored (another account, say). Updating
    /// whatever sits at `key` then would give the new body the old record's response, and its
    /// credential digests with it.
    mutating func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        expecting expected: CachedResponse,
        maximumCapacity: Int64
    ) {
        guard
            let record = records[key],
            record.cachedResponse.isSameEntry(as: expected),
            // Not rewritten when it was already renewed after `expected` was read: by a revalidation
            // that ran alongside this one, and just as good. Writing this one's older date over it
            // would only take the entry back in time.
            record.cachedResponse.date <= expected.date
        else {
            return
        }

        var newRecord = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        newRecord.dataURL = record.dataURL
        newRecord.isFinished = record.isFinished

        records[key] = newRecord
    }

    /// Reserves a slot and hands back the location its bytes go to.
    ///
    /// - Parameter knownUsage: A caller-tracked usage estimate, passed straight through to
    /// `freeSpace(_:knownUsage:)` to let it skip its scan when usage is already known to fit.
    /// See that method's doc for the safety argument.
    /// - Returns: The store the caller should open a buffer over (`nil` when the entry does not
    /// fit) and usage immediately after this call, for the caller to keep as its next
    /// `knownUsage`.
    ///
    /// - Important: Must not be `async`, and must not return the buffer itself. This type is only
    /// reachable through `withMemoryStorage`, which hands out an `inout` from inside a non
    /// reentrant lock, and a synchronous closure cannot await. A method whose only suspension
    /// point is building the `Internals.DataBuffer` would be impossible to call from there.
    ///
    /// Returning the location instead keeps the bookkeeping under the lock and lets the buffer
    /// be built outside it, so the lock isn't held across buffer construction.
    mutating func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) -> (dataURL: Internals.ByteURL?, usage: Int64?) {
        let (dataURL, usage, _) = allocateBufferReplacing(
            key: key,
            cachedResponse: cachedResponse,
            contentLength: contentLength,
            maximumCapacity: maximumCapacity,
            knownUsage: knownUsage
        )

        return (dataURL, usage)
    }

    /// ``allocateBuffer(key:cachedResponse:contentLength:maximumCapacity:knownUsage:)``, which also
    /// says which record it replaced, for ``restore(_:forKey:ifDataURL:)``.
    mutating func allocateBufferReplacing(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) -> (dataURL: Internals.ByteURL?, usage: Int64?, replaced: Record?) {
        // `contentLength` comes from a response's `Content-Length`, which a server controls.
        // A negative one is no size at all, and `Int64.min` would overflow the subtraction below
        // and trap, so it is turned down like an entry that does not fit, as `DiskStorage` does.
        guard contentLength >= 0, contentLength <= maximumCapacity else {
            return (nil, nil, nil)
        }

        let usageAfterEviction = freeSpace(maximumCapacity - contentLength, knownUsage: knownUsage)

        let record = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        // What an earlier write of the key left in the middle is not something to go back to: its
        // body is partial, and if that write fails too, nothing would ever complete it.
        let replaced = records[key].flatMap { $0.isFinished ? $0 : nil }
        records[key] = record

        return (record.dataURL, usageAfterEviction + contentLength, replaced)
    }

    /// Marks the record at `key` as whole, when it is still the one `dataURL` identifies: the write
    /// that allocated it has written its whole body.
    mutating func finish(_ key: String, ifDataURL dataURL: Internals.ByteURL) {
        guard records[key]?.dataURL === dataURL else {
            return
        }

        records[key]?.isFinished = true
    }

    /// Puts back the record that a write replaced, when that write is given up on and its own
    /// record, the one `dataURL` identifies, is still what sits at `key`.
    ///
    /// A write that fails leaves the entry it was going to replace as it was, in this tier as it
    /// does in the disk one. Nothing is restored over a record that a later write installed.
    mutating func restore(_ replaced: Record, forKey key: String, ifDataURL dataURL: Internals.ByteURL) {
        guard records[key]?.dataURL === dataURL else {
            return
        }

        records[key] = replaced
    }

    /// Installs a record whose bytes are already in `dataURL`, for an entry that was read from
    /// another tier and is being kept here.
    ///
    /// Unlike ``allocateBuffer(key:cachedResponse:contentLength:maximumCapacity:knownUsage:)``,
    /// the entry is complete from the moment it is visible, so a reader never meets it half
    /// written.
    ///
    /// - Returns: Whether the entry was installed (`false` when it does not fit), and usage
    /// immediately after this call, for the caller to keep as its next `knownUsage`.
    mutating func install(
        key: String,
        cachedResponse: CachedResponse,
        dataURL: Internals.ByteURL,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) -> (installed: Bool, usage: Int64?) {
        let size = Int64(dataURL.writtenBytes)

        guard size <= maximumCapacity else {
            return (false, nil)
        }

        let usageAfterEviction = freeSpace(maximumCapacity - size, knownUsage: knownUsage)

        var record = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        record.dataURL = dataURL
        record.isFinished = true
        records[key] = record

        return (true, usageAfterEviction + size)
    }

    /// Evicts the least recently used entries, if any, until usage is at or under
    /// `maximumCapacity`. An entry is used when it is written, revalidated or served.
    ///
    /// - Parameter knownUsage: A caller-tracked usage estimate. When it already fits under
    /// `maximumCapacity`, the full scan below is skipped, since nothing would be evicted anyway.
    /// Mirrors `DiskStorage.freeSpace(_:knownUsage:)`'s short-circuit and safety argument (see
    /// that method's doc), which avoids paying the O(current entry count) scan on every write
    /// and turning a cache's whole lifetime into O(n²).
    ///
    /// Entries are ordered by `Record.lastUsed` here instead of maintaining a reorderable index
    /// that every `allocateBuffer`/`updateCached` call would have to update, as
    /// `DiskStorage.freeSpace` does for its own records. Sorting is paid only on this guarded
    /// rescan path, not as an O(current entry count) shift on every write.
    ///
    /// - Returns: Usage immediately after this call: either the untouched `knownUsage` when
    /// skipped, or the freshly measured total otherwise.
    @discardableResult
    mutating func freeSpace(_ maximumCapacity: Int64, knownUsage: Int64? = nil) -> Int64 {
        if let knownUsage, knownUsage <= maximumCapacity {
            return knownUsage
        }

        if maximumCapacity == .zero {
            records = [:]
            return .zero
        }

        var accumulatedSize: Int64 = 0
        var deleteOnly = false

        for entry in records.values.sorted(by: { $0.lastUsed > $1.lastUsed }) {
            if !deleteOnly, accumulatedSize + entry.size <= maximumCapacity {
                accumulatedSize += entry.size
                continue
            }

            deleteOnly = true
            records[entry.key] = nil
        }

        return accumulatedSize
    }
}
