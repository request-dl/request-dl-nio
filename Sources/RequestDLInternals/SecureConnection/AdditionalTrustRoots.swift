/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct AdditionalTrustRoots {

    let sources: [AdditionalTrustRootSource]

    public init(_ sources: [AdditionalTrustRootSource]) {
        self.sources = sources
    }
}

extension AdditionalTrustRoots {

    func build() throws -> [NIOSSLAdditionalTrustRoots] {
        try sources.map {
            try $0.build()
        }
    }
}
