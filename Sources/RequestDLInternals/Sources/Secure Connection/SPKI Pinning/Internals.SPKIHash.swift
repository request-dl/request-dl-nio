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

        /// Named algorithms `URLSessionClient`'s `SecTrust`-based trust evaluation can recompute
        /// on its own -- `Data`/`Codable`, unlike `Algorithm.Type`, so a `ServerTrustPolicy` built
        /// from one of these can also survive a `BackgroundDownloadTask` relaunch as a
        /// `ServerTrustPolicy.Descriptor`. Every hash algorithm actually documented for
        /// `RequestDL.SPKIHash` (SHA-256/384/512); anything else still pins correctly for the
        /// lifetime of the process that configured it (`matchesSPKI` never needs this), it just
        /// can't be captured into a `Descriptor`.
        package enum KnownAlgorithm: String, Sendable, Codable, Hashable {
            case sha256
            case sha384
            case sha512
        }

        private let source: SPKIHashSource

        private let algorithmID: ObjectIdentifier
        private let producer: @Sendable (SPKIHashSource) throws -> AsyncHTTPClient.SPKIHash
        private let digest: @Sendable (Data) -> Data

        package let knownAlgorithm: KnownAlgorithm?

        package init<Algorithm: HashFunction>(
            source: SPKIHashSource,
            algorithm: Algorithm.Type
        ) {
            self.source = source
            self.algorithmID = .init(algorithm)
            self.producer = {
                try AsyncHTTPClient.SPKIHash(algorithm: algorithm, source: $0)
            }
            self.digest = { Data(algorithm.hash(data: $0)) }

            switch algorithm {
            case is SHA256.Type: self.knownAlgorithm = .sha256
            case is SHA384.Type: self.knownAlgorithm = .sha384
            case is SHA512.Type: self.knownAlgorithm = .sha512
            default: self.knownAlgorithm = nil
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

        /// The digest this pin expects the peer's SPKI to hash to -- what `ServerTrustPolicy`
        /// compares against, and what a `Descriptor` persists for `knownAlgorithm != nil` pins.
        package func resolvedDigest() throws -> Data {
            try producer(source).bytes
        }

        /// Whether `spkiDERBytes` (the SPKI structure `NIOSSLPublicKey.toSPKIBytes()` produces for
        /// a peer's leaf certificate) hashes to this pin's configured digest. Constant-time, same
        /// rationale as AsyncHTTPClient's own SPKI pin comparison: a length or byte mismatch here
        /// should not be distinguishable by timing from a match.
        package func matchesSPKI(_ spkiDERBytes: Data) throws -> Bool {
            let target = try resolvedDigest()
            let computed = digest(spkiDERBytes)

            guard computed.count == target.count else {
                return false
            }

            var difference: UInt8 = 0
            for (lhs, rhs) in zip(computed, target) {
                difference |= lhs ^ rhs
            }
            return difference == 0
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
