//
// See LICENSE for this package's licensing information.
//

/// Thrown while reading ``AsyncBytes/lines(maximumLength:)``,
/// ``AsyncBytes/items(separatedBy:maximumLength:)-([UInt8],_)`` or
/// ``AsyncBytes/events(maximumLineLength:)``, when one item grew past its maximum without ending.
///
/// The items that ended before it have already been delivered. The sequence ends with this error
/// and reads nothing more.
public struct AsyncBytesItemTooLargeError: Error, Sendable, Hashable, CustomStringConvertible {

    /// The limit that was exceeded, in bytes, not counting the delimiter that would have ended
    /// the item.
    public let maximumLength: Int

    public var description: String {
        "An item read from AsyncBytes grew past \(maximumLength) bytes without ending."
    }

    init(maximumLength: Int) {
        self.maximumLength = maximumLength
    }
}
