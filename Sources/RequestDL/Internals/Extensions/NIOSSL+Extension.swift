/*
 See LICENSE for this package's licensing information.
*/

import NIOSSL

extension TLSConfiguration: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        "\(lhs)" == "\(rhs)"
    }
}
