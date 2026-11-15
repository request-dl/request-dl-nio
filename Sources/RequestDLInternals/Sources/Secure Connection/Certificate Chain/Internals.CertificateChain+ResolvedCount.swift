//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import class Foundation.FileManager
#endif

extension Internals.CertificateChain {

    /// How many certificates this chain resolves to, or `nil` when it cannot be resolved (an
    /// unreadable file, data that is not PEM): building the identity reports that, with its own
    /// error.
    ///
    /// `resolvedDERBytes()` reads and parses the PEM. This is asked on every request, to choose
    /// the executor, so the answer is remembered for as long as the chain and the files it names
    /// stay as they are (a file's modification date and size are what tell).
    package var resolvedCertificateCount: Int? {
        ResolvedCountCache.shared.count(of: self)
    }

    /// Every file this chain reads, in order.
    fileprivate var filePaths: [String] {
        switch self {
        case .file(let path):
            return [path]
        case .bytes:
            return []
        case .certificates(let certificates):
            return certificates.compactMap {
                if case .file(let path) = $0.source {
                    return path
                }
                return nil
            }
        }
    }
}

private final class ResolvedCountCache: @unchecked Sendable {

    static let shared = ResolvedCountCache()

    /// Enough for every configuration a process realistically alternates between; emptied rather
    /// than evicted one by one when it is exceeded, since the next request just recounts.
    private static let capacity = 64

    private struct FileStamp: Hashable {
        let path: String
        let modificationDate: Date?
        let size: String
    }

    private struct Entry {
        let stamps: [FileStamp]
        let count: Int
    }

    private let lock = Lock()
    private var entries: [Internals.CertificateChain: Entry] = [:]

    func count(of chain: Internals.CertificateChain) -> Int? {
        let stamps = chain.filePaths.map(Self.stamp(ofFileAt:))

        if let cached = lock.withLock({ entries[chain] }), cached.stamps == stamps {
            return cached.count
        }

        guard let count = try? chain.resolvedDERBytes().count else {
            return nil
        }

        lock.withLock {
            if entries.count >= Self.capacity {
                entries.removeAll()
            }
            entries[chain] = Entry(stamps: stamps, count: count)
        }

        return count
    }

    private static func stamp(ofFileAt path: String) -> FileStamp {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)

        return FileStamp(
            path: path,
            modificationDate: attributes?[.modificationDate] as? Date,
            size: attributes?[.size].map { String(describing: $0) } ?? ""
        )
    }
}
