/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct MemoryStorage: Sendable {

    private struct Record: Sendable, Hashable {

        // MARK: - Internal properties

        var size: UInt64 {
            UInt64(dataURL.writtenBytes)
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
            self.date = Date()
            self.cachedResponse = cachedResponse
            self.dataURL = .init()
        }
    }

    // MARK: - Private properties

    private let directory: URL
    private var identifiers = Set<String>()
    private var records = [String: Record]()

    // MARK: - Inits

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Internal methods

    subscript(_ key: String) -> CachedData? {
        guard let record = records[key] else {
            return nil
        }

        return .init(
            cachedResponse: record.cachedResponse,
            buffer: Internals.DataBuffer(record.dataURL)
        )
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

            if entry.date < date {
                identifiers.remove(key)
                records[key] = nil
            }
        }
    }

    mutating func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        maximumCapacity: UInt64
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
        identifiers.insert(key)
    }

    mutating func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: UInt64,
        maximumCapacity: UInt64
    ) -> Internals.AnyBuffer? {
        guard contentLength <= maximumCapacity else {
            return nil
        }

        freeSpace(maximumCapacity - contentLength)

        let record = Record(
            key: key,
            cachedResponse: cachedResponse
        )

        identifiers.remove(key)
        identifiers.insert(key)

        records[key] = record

        return Internals.DataBuffer(record.dataURL)
    }

    mutating func freeSpace(_ maximumCapacity: UInt64) {
        var accumulatedSize: UInt64 = 0
        var deleteOnly = false

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
