/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct AdditionalTrustRoots {

    private(set) var sources: [AdditionalTrustRootSource]

    public init(_ sources: [AdditionalTrustRootSource]) {
        self.sources = sources
    }

    public init() {
        self.init([])
    }

    public mutating func append(_ source: AdditionalTrustRootSource) {
        sources.append(source)
    }
}

extension AdditionalTrustRoots {

    func build() throws -> [NIOSSLAdditionalTrustRoots] {
        try sources.map {
            try $0.build()
        }
    }
}
