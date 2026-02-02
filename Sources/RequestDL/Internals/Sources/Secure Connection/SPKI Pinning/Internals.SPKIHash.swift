//
//  Internals.SPKIHash.swift
//  request-dl
//
//  Created by Brenno de Moura on 02/02/26.
//

import Foundation
import AsyncHTTPClient
import Crypto

extension Internals {

    struct SPKIHash: Sendable, Hashable {

        let anchor: SPKIHashAnchor
        private let source: SPKIHashSource

        private let algorithmID: ObjectIdentifier
        private let producer: @Sendable (SPKIHashSource) throws -> AsyncHTTPClient.SPKIHash

        init<Algorithm: HashFunction>(
            anchor: SPKIHashAnchor,
            source: SPKIHashSource,
            algorithm: Algorithm.Type
        ) {
            self.anchor = anchor
            self.source = source
            self.algorithmID = .init(algorithm)
            self.producer = {
                try AsyncHTTPClient.SPKIHash(algorithm: algorithm, source: $0)
            }
        }

        static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.anchor == rhs.anchor
                && lhs.source == rhs.source
                && lhs.algorithmID == rhs.algorithmID
        }

        func resolve(_ tlsPins: inout [SPKIHashAnchor: [AsyncHTTPClient.SPKIHash]]) throws {
            let hash = try producer(source)
            tlsPins[anchor, default: []].append(hash)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(anchor)
            hasher.combine(source)
            hasher.combine(algorithmID)
        }
    }
}

extension Internals {

    enum SPKIHashSource: Sendable, Hashable {
        case base64String(String)
        case rawData(Data)
    }
}

private extension AsyncHTTPClient.SPKIHash {

    init<Algorithm: HashFunction>(
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
