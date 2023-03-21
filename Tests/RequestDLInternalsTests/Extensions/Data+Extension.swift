/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Data {

    static func randomData(length: Int) -> Data {
        let seed: UInt8 = (.min ... .max).randomElement() ?? .min
        return Data(repeating: seed, count: length)
    }
}


