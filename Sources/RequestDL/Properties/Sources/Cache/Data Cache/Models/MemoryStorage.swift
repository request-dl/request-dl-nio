//
// See LICENSE for this package's licensing information.
//

import Collections

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

    mutating func removeAll() {
        identifiers = []
        records = [:]
    }

    mutating func removeAll(since date: Date) {
        for key in identifiers {
            guard let entry = records[key] else {
                fatalError()
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
    /// - Returns: The store the caller should open a buffer over, or `nil` when the entry does
    /// not fit.
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
        maximumCapacity: Int64
    ) -> Internals.ByteURL? {
        guard contentLength <= maximumCapacity else {
            return nil
        }

        freeSpace(maximumCapacity - contentLength)

        let record = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        identifiers.remove(key)
        identifiers.append(key)

        records[key] = record

        return record.dataURL
    }

    mutating func freeSpace(_ maximumCapacity: Int64) {
        var accumulatedSize: Int64 = 0
        var deleteOnly = maximumCapacity == .zero

        for key in identifiers.reversed() {
            guard let entry = records[key] else {
                identifiers.remove(key)
                continue
            }

            if !deleteOnly {
                accumulatedSize += entry.size
            }

            if deleteOnly || accumulatedSize > maximumCapacity {
                deleteOnly = true
                records[key] = nil
                identifiers.remove(key)
            }
        }
    }
}
