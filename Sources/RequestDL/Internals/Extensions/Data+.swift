/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Data {

    func safeLogDescription(maxLength: Int = 500) -> String {
        if count > maxLength * 2 {
            return "<data: \(count) bytes (too large to display)>"
        }

        guard let string = String(data: self, encoding: .utf8) else {
            return "<binary data: \(count) bytes>"
        }

        if string.count <= maxLength {
            return string.isEmpty ? "<empty>" : string
        } else {
            return String(string.prefix(maxLength)) + "…"
        }
    }
}
