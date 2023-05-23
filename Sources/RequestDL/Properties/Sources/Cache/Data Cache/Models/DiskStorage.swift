/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct DiskStorage: Sendable {

    private struct Records: Sequence, Sendable {

        struct Iterator: IteratorProtocol {

            // MARK: - Internal properties

            var urls: [URL]

            // MARK: - Internal methods

            mutating func next() -> Record? {
                while let url = urls.first {
                    urls.removeFirst()

                    if let record = Record(url) {
                        return record
                    }
                }

                return nil
            }
        }

        // MARK: - Internal properties

        let directory: URL
        let keys: [URLResourceKey]

        // MARK: - Internal methods

        func makeIterator() -> Iterator {
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys
            )

            return .init(urls: urls ?? [])
        }
    }

    struct Record: Sendable {

        // MARK: - Internal static properties

        static let pathExtension = "cached"

        // MARK: - Private static properties

        private static let responsePath = "response.record"
        private static let dataPath = "data.record"

        // MARK: - Internal properties

        var size: UInt64 {
            do {
                let cachedValues = try responseURL.resourceValues(forKeys: [.fileSizeKey])
                let dataValues = try dataURL.resourceValues(forKeys: [.fileSizeKey])

                let cachedSize = UInt64(cachedValues.fileSize ?? .zero)
                let dataSize = UInt64(dataValues.fileSize ?? .zero)

                return cachedSize + dataSize
            } catch {
                return .zero
            }
        }

        let key: String
        let url: URL
        let date: Date

        let responseURL: URL
        let dataURL: URL

        // MARK: - Inits

        init?(_ url: URL) {
            guard
                url.pathExtension == Self.pathExtension,
                let (key, date) = Self.getKeyAndDate(url),
                let (responseURL, dataURL) = Self.getResponseAndDataCachedURLs(url)
            else { return nil }

            self.date = date
            self.key = key
            self.url = url
            self.responseURL = responseURL
            self.dataURL = dataURL
        }

        init(
            directory: URL,
            key: String,
            at date: Date
        ) {
            let timeUnit = Int(date.timeIntervalSinceReferenceDate)

            let url = directory
                .appendingPathComponent(String(timeUnit, radix: 36) + "." + key)
                .appendingPathExtension(DiskStorage.Record.pathExtension)

            self.url = url
            self.key = key
            self.date = date

            let responseURL = url.appendingPathComponent(DiskStorage.Record.responsePath)
            let dataURL = url.appendingPathComponent(DiskStorage.Record.dataPath)

            self.responseURL = responseURL
            self.dataURL = dataURL

            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {}
        }

        // MARK: - Private static methods

        private static func getKeyAndDate(_ url: URL) -> (String, Date)? {
            var components = url
                .deletingPathExtension()
                .lastPathComponent
                .split(separator: ".")

            guard let time = components.first.flatMap({ Int64($0, radix: 36) }) else {
                return nil
            }

            components.removeFirst()

            return (
                components.joined(separator: "."),
                Date(timeIntervalSinceReferenceDate: TimeInterval(time))
            )
        }

        private static func getResponseAndDataCachedURLs(_ url: URL) -> (URL, URL)? {
            guard
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey]
                ),
                contents.count == 2,
                let responseURL = contents.first(where: { $0.lastPathComponent == Self.responsePath }),
                let dataURL = contents.first(where: { $0.lastPathComponent == Self.dataPath })
            else { return nil }

            return (responseURL, dataURL)
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
        guard
            let record = record(key),
            let responseData = try? Data(contentsOf: record.responseURL),
            let cachedResponse = try? JSONDecoder().decode(CachedResponse.self, from: responseData)
        else { return nil }

        return .init(
            cachedResponse: cachedResponse,
            buffer: Internals.FileBuffer(record.dataURL)
        )
    }

    func remove(_ key: String) {
        guard let record = record(key) else {
            return
        }

        try? FileManager.default.removeItem(at: record.url)
    }

    func removeAll() {
        freeSpace(.zero)
    }

    func removeAll(since date: Date) {
        for record in records() where record.date <= date {
            try? FileManager.default.removeItem(at: record.url)
        }
    }

    func updateCached(
        key: String,
        cachedResponse: CachedResponse,
        maximumCapacity: UInt64
    ) {
        guard
            let record = record(key),
            let response = try? JSONEncoder().encode(cachedResponse)
        else { return }

        let responseLength = try? record.responseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let spaceChange = response.count - (responseLength ?? .zero)
        let spaceNeeded = UInt64(spaceChange < .zero ? .zero : spaceChange)

        guard spaceNeeded <= maximumCapacity else {
            return
        }

        freeSpace(maximumCapacity - spaceNeeded)

        guard
            record.dataURL.isReachable,
            let newRecord = self.record(key, createdAt: cachedResponse.date)
        else { return }

        do {
            try FileManager.default.moveItem(
                at: record.dataURL,
                to: newRecord.dataURL
            )

            try response.write(to: newRecord.responseURL)
        } catch {
            try? FileManager.default.removeItem(at: newRecord.url)
        }

        try? FileManager.default.removeItem(at: record.url)
    }

    func allocateBuffer(
        key: String,
        cachedResponse: CachedResponse,
        contentLength: UInt64,
        maximumCapacity: UInt64
    ) -> Internals.AnyBuffer? {
        guard let response = try? JSONEncoder().encode(cachedResponse) else {
            return nil
        }

        let writableBytes = UInt64(response.count) + contentLength

        guard writableBytes <= maximumCapacity else {
            return nil
        }

        freeSpace(maximumCapacity - writableBytes)

        guard let record = record(key, createdAt: cachedResponse.date) else {
            return nil
        }

        try? response.write(to: record.responseURL)
        return Internals.FileBuffer(record.dataURL)
    }

    func freeSpace(_ maximumCapacity: UInt64) {
        let entries = records(including: [.fileSizeKey]).sorted {
            $0.date > $1.date
        }

        var accumulatedSize: UInt64 = 0
        var deleteOnly = false

        for entry in entries {
            if !deleteOnly {
                accumulatedSize += entry.size
            }

            if deleteOnly || accumulatedSize > maximumCapacity {
                deleteOnly = true
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    // MARK: - Private methods

    private func record(_ key: String, createdAt date: Date? = nil) -> Record? {
        switch date {
        case .none:
            return records().first {
                $0.key == key
            }
        case .some(let date):
            return .init(directory: directory, key: key, at: date)
        }
    }

    private func records(including keys: [URLResourceKey] = []) -> Records {
        Records(
            directory: directory,
            keys: keys
        )
    }
}
