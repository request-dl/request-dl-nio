//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOFileSystem
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
import NIOFoundationEssentialsCompat
#else
// import struct Foundation.URL
// import struct Foundation.Date
// import struct Foundation.Data
// import class Foundation.JSONDecoder
// import class Foundation.JSONEncoder
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

                let responseInfo = try? await FileSystem.shared.info(forFileAt: responsePath)
                let dataInfo = try? await FileSystem.shared.info(forFileAt: dataPath)

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
            let responseExists = (try? await FileSystem.shared.info(forFileAt: responseURL.filePath)) != nil
            let dataExists = (try? await FileSystem.shared.info(forFileAt: dataURL.filePath)) != nil

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
                try await FileSystem.shared.createDirectory(
                    at: url.filePath,
                    withIntermediateDirectories: true
                )
            } catch {
                // Silent. Whoever writes through this record reports the failure with context.
            }
        }

        // MARK: - Private static methods

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
    private func readResponseData(at url: URL) async -> Data? {
        guard let handle = try? await FileSystem.shared.openFile(forReadingAt: url.filePath) else {
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

    func remove(_ key: String) async {
        guard let record = await record(key) else { return }
        _ = try? await FileSystem.shared.removeItem(
            at: record.url.filePath
        )
    }

    func removeAll() async {
        await freeSpace(.zero)
    }

    func removeAll(since date: Date) async {
        let recordsToCheck = await records()
        for record in recordsToCheck where record.date <= date {
            _ = try? await FileSystem.shared.removeItem(
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

        let responseInfo = try? await FileSystem.shared.info(forFileAt: record.responseURL.filePath)
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
            try await FileSystem.shared.moveItem(at: oldDataPath, to: newDataPath)

            try await writeAndClose(response, to: newRecord.responseURL)
        } catch {
            _ = try? await FileSystem.shared.removeItem(
                at: newRecord.url.filePath
            )
        }

        _ = try? await FileSystem.shared.removeItem(
            at: record.url.filePath
        )
    }

    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: Int64,
        maximumCapacity: Int64
    ) async -> Internals.AnyBuffer? {
        guard let response = try? JSONEncoder().encode(cachedResponse) else { return nil }

        let writableBytes = Int64(response.count) + contentLength
        guard writableBytes <= maximumCapacity else { return nil }

        await freeSpace(maximumCapacity - writableBytes)

        guard let record = await record(key, createdAt: cachedResponse.date) else { return nil }

        do {
            try await writeAndClose(response, to: record.responseURL)
        } catch {
            return nil
        }

        return await Internals.FileBuffer(record.dataURL)
    }

    func freeSpace(_ maximumCapacity: Int64) async {
        var entries = await records()

        if maximumCapacity == .zero {
            for entry in entries {
                _ = try? await FileSystem.shared.removeItem(at: entry.url.filePath)
            }
            return
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
            _ = try? await FileSystem.shared.removeItem(
                at: entry.url.filePath
            )
            totalSize -= size
        }
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
    /// let handle = try await FileSystem.shared.openFile(...)
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
        let handle = try await FileSystem.shared.openFile(
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
            try await FileSystem.shared.withDirectoryHandle(atPath: dirPath) { dir in
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
