//
// See LICENSE for this package's licensing information.
//

import NIOCore
// `NIOFileSystem` is the public module; `_NIOFileSystem` is the underscored implementation
// target it re-exports.
import NIOFileSystem
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Date
import struct Foundation.Data
import struct Foundation.TimeInterval
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
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
            let timeUnit = Int(date.timeIntervalSinceReferenceDate)
            var directoryPathComponent = String(timeUnit, radix: 36)
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
            guard let time = components.first.flatMap({ Int64($0, radix: 36) }) else { return nil }
            components.removeFirst()
            return (components.joined(separator: "."), Date(timeIntervalSinceReferenceDate: TimeInterval(time)))
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

            let responsePath = record.responseURL.filePath
            guard
                let handle = try? await FileSystem.shared.openFile(forReadingAt: responsePath),
                let buffer = try? await handle.readToEnd(maximumSizeAllowed: .unlimited)
            else { return nil }

            let responseData =
                buffer.getData(
                    at: buffer.readerIndex,
                    length: buffer.readableBytes
                ) ?? Data()

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

            let newResponsePath = newRecord.responseURL.filePath
            let handle = try await FileSystem.shared.openFile(
                forWritingAt: newResponsePath,
                options: .newFile(replaceExisting: true)
            )
            try await handle.write(contentsOf: response, toAbsoluteOffset: .zero)
            try await handle.close()
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
            let responsePath = record.responseURL.filePath
            let handle = try await FileSystem.shared.openFile(
                forWritingAt: responsePath,
                options: .newFile(replaceExisting: true)
            )
            try await handle.write(contentsOf: response, toAbsoluteOffset: .zero)
            try await handle.close()
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

        // Ordena do mais antigo para o mais novo (LRU: Least Recently Used)
        entries.sort { $0.date < $1.date }

        // Calcula o tamanho total atual
        var totalSize: Int64 = 0
        var entrySizes: [(Record, Int64)] = []
        for entry in entries {
            let size = await entry.size
            totalSize += size
            entrySizes.append((entry, size))
        }

        // Remove os mais antigos até que o tamanho total esteja dentro da capacidade
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
            // 1. Abre um handle para o diretório
            try await FileSystem.shared.withDirectoryHandle(atPath: dirPath) { dir in
                // 2. Lista o conteúdo através do handle do diretório
                for try await entry in dir.listContents() {
                    // entry.name é um FilePath.Component, usamos .string para obter o texto
                    if entry.name.string.hasSuffix(".\(Record.pathExtension)") {
                        let entryURL = directory.appendingPathComponent(entry.name.string)

                        if let record = await Record(entryURL) {
                            foundRecords.append(record)
                        }
                    }
                }
            }
        } catch {
            // Ignora erros de listagem (ex: diretório não existe ainda)
        }

        return foundRecords
    }
}
