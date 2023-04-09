/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension String {

    private static func shifted(_ shifting: Int) -> String {
        guard shifting > .zero else {
            return ""
        }

        return String(repeating: " ", count: shifting)
    }

    func debug_shiftLines(_ shifting: Int = 4) -> String {
        split(separator: "\n")
            .map { "\(Self.shifted(shifting))\($0)" }
            .joined(separator: "\n")
    }
}
