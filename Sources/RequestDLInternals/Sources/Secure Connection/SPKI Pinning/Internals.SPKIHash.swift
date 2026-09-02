//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Crypto

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    package struct SPKIHash: Sendable, Hashable {

        private let source: SPKIHashSource

        private let algorithmID: ObjectIdentifier
        private let producer: @Sendable (SPKIHashSource) throws -> AsyncHTTPClient.SPKIHash

        package init<Algorithm: HashFunction>(
            source: SPKIHashSource,
            algorithm: Algorithm.Type
        ) {
            self.source = source
            self.algorithmID = .init(algorithm)
            self.producer = {
                try AsyncHTTPClient.SPKIHash(algorithm: algorithm, source: $0)
            }
        }

        package static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.source == rhs.source
                && lhs.algorithmID == rhs.algorithmID
        }

        package func resolve(_ tlsPins: inout [AsyncHTTPClient.SPKIHash]) throws {
            let hash = try producer(source)
            tlsPins.append(hash)
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(source)
            hasher.combine(algorithmID)
        }
    }
}

extension Internals {

    package enum SPKIHashSource: Sendable, Hashable {
        case base64String(String)
        case rawData(Data)
    }
}

extension AsyncHTTPClient.SPKIHash {

    fileprivate init<Algorithm: HashFunction>(
        algorithm: Algorithm.Type,
        source: Internals.SPKIHashSource
    ) throws {
        switch source {
        case .base64String(let base64):
            try self.init(algorithm: algorithm, base64: base64)
        case .rawData(let bytes):
            try self.init(algorithm: algorithm, bytes: bytes)
        }
    }
}
