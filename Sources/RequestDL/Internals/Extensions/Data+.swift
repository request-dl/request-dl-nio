//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

extension Data {

    /// A description safe to put in a log line.
    ///
    /// Three outcomes: too large to be worth showing, not text, or the text itself, truncated.
    ///
    /// - Parameter maxLength: Characters of text to show. Anything past twice that in bytes is
    /// reported by size alone and never decoded, which is the cheap path for a response body.
    func safeLogDescription(maxLength: Int = 500) -> String {
        if count > maxLength * 2 {
            return "<data: \(count) bytes (too large to display)>"
        }

        // `String(decoding:as:)` substitutes U+FFFD for anything malformed instead of failing,
        // so validity is checked by round-tripping. `String(data:encoding:)` would also work,
        // but it needs `String.Encoding`, which is not part of `FoundationEssentials`.
        let string = String(decoding: self, as: UTF8.self)

        guard string.utf8.elementsEqual(self) else {
            return "<binary data: \(count) bytes>"
        }

        guard string.count > maxLength else {
            return string.isEmpty ? "<empty>" : string
        }

        return String(string.prefix(maxLength)) + "…"
    }
}
