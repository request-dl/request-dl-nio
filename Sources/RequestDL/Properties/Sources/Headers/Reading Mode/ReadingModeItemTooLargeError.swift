//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Thrown while reading a download whose ``ReadingMode`` has a separator and a
/// `maximumItemSize`, when one item grew past that size without ending.
///
/// The items that ended before it have already been delivered. The rest of the response is not
/// read.
public struct ReadingModeItemTooLargeError: Error, Sendable, Hashable, CustomStringConvertible {

    /// The limit that was exceeded, in bytes. It counts the separator.
    public let maximumItemSize: Int

    public var description: String {
        "An item read with ReadingMode(separator:maximumItemSize:) grew past \(maximumItemSize) bytes without ending."
    }

    init(maximumItemSize: Int) {
        self.maximumItemSize = maximumItemSize
    }

    init(_ error: Internals.ReadingModeItemTooLargeError) {
        self.init(maximumItemSize: error.maximumItemSize)
    }
}
