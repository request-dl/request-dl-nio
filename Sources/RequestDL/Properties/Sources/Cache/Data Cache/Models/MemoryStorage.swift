//
// See LICENSE for this package's licensing information.
//

import Collections
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.URL
#endif

struct MemoryStorage: Sendable {

    private struct Record: Sendable, Hashable {

        // MARK: - Internal properties

        var size: Int64 {
            Int64(dataURL.writtenBytes)
        }

        let key: String
        let date: Date

        let cachedResponse: CachedResponse
        var dataURL: Internals.ByteURL

        // MARK: - Inits

        init(
            key: String,
            cachedResponse: CachedResponse
        ) {
            self.key = key
            self.date = cachedResponse.date
            self.cachedResponse = cachedResponse
            self.dataURL = .init()
        }
    }

    // MARK: - Private properties

    private let directory: URL
    private var identifiers = OrderedSet<String>()
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

    mutating func remove(_ key: String) {
        identifiers.remove(key)
        records[key] = nil
    }

    /// Removes `key` only if its currently stored record is still the exact one `dataURL`
    /// identifies, mirroring `DiskStorage.Index.remove(_:ifLocation:)`.
    ///
    /// A plain `remove(_:)` would blindly delete whatever record currently sits at `key`, even
    /// one a concurrent, still-in-progress write for the same key just installed after this
    /// caller's own write started. `ByteURL` is a class — its identity, not its bytes, is what a
    /// caller who allocated a specific record can still prove it owns that record by the time it
    /// wants to discard it.
    mutating func remove(_ key: String, ifDataURL dataURL: Internals.ByteURL) {
        guard records[key]?.dataURL === dataURL else {
            return
        }

        identifiers.remove(key)
        records[key] = nil
    }

    mutating func removeAll() {
        identifiers = []
        records = [:]
    }

    mutating func removeAll(since date: Date) {
        for key in identifiers {
            // Mirrors `freeSpace`'s handling of the same `identifiers`/`records` pairing: treat a
            // missing record as already evicted rather than trapping, so both methods agree on
            // what to do with a stale identifier.
            guard let entry = records[key] else {
                identifiers.remove(key)
                continue
            }

            if entry.date <= date {
                identifiers.remove(key)
                records[key] = nil
            }
        }
    }

    mutating func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        maximumCapacity: Int64
    ) {
        guard let record = records[key] else {
            return
        }

        var newRecord = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        newRecord.dataURL = record.dataURL

        identifiers.remove(key)
        records[key] = newRecord
        identifiers.append(key)
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
    /// - Important: Must not be `async`, and must not return the buffer itself. This type is
    /// only reachable through `withMemoryStorage`, which hands out an `inout` from inside a non
    /// reentrant lock, and a synchronous closure cannot await — so a method whose only
    /// suspension point is building the `Internals.DataBuffer` itself would be a method its only
    /// caller could not call.
    ///
    /// Returning the location instead lets the bookkeeping stay under the lock, where it
    /// belongs, and the buffer be built outside it. That also stops the lock being held across
    /// buffer construction.
    mutating func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64,
        knownUsage: Int64? = nil
    ) -> (dataURL: Internals.ByteURL?, usage: Int64?) {
        guard contentLength <= maximumCapacity else {
            return (nil, nil)
        }

        let usageAfterEviction = freeSpace(maximumCapacity - contentLength, knownUsage: knownUsage)

        let record = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        identifiers.remove(key)
        identifiers.append(key)

        records[key] = record

        return (record.dataURL, usageAfterEviction + contentLength)
    }

    /// Evicts the oldest entries, if any, until usage is at or under `maximumCapacity`.
    ///
    /// - Parameter knownUsage: A caller-tracked usage estimate. When it already fits under
    /// `maximumCapacity`, the full scan below (and the `OrderedSet.remove(_:)` cost of any
    /// eviction it would have found) is skipped outright, since nothing would be evicted anyway.
    /// Mirrors `DiskStorage.freeSpace(_:knownUsage:)`'s own short-circuit and safety argument —
    /// see that method's doc — for the same O(current entry count) cost this would otherwise pay
    /// on every single cache write, `n` of them turning a cache's whole lifetime into O(n²).
    ///
    /// - Returns: Usage immediately after this call: either the untouched `knownUsage` when
    /// skipped, or the freshly measured total otherwise.
    @discardableResult
    mutating func freeSpace(_ maximumCapacity: Int64, knownUsage: Int64? = nil) -> Int64 {
        if let knownUsage, knownUsage <= maximumCapacity {
            return knownUsage
        }

        var accumulatedSize: Int64 = 0
        var deleteOnly = maximumCapacity == .zero

        for key in identifiers.reversed() {
            guard let entry = records[key] else {
                identifiers.remove(key)
                continue
            }

            if !deleteOnly, accumulatedSize + entry.size <= maximumCapacity {
                accumulatedSize += entry.size
                continue
            }

            deleteOnly = true
            records[key] = nil
            identifiers.remove(key)
        }

        return accumulatedSize
    }
}
