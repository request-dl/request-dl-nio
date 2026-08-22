//
// See LICENSE for this package's licensing information.
//

/// An error thrown by ``RequestDL/Payload/init(url:from:contentType:)`` when the requested
/// offset does not fit within the file's current size.
///
/// Typically means the file was truncated or replaced since the offset was recorded, e.g. by a
/// previous, partially completed upload attempt.
public struct InvalidPayloadOffsetError: Sendable, Error {

    /// The offset that was requested.
    public let offset: UInt64

    /// The number of bytes available in the file at the time of the request.
    public let availableBytes: Int

    ///
    /// Initializes a new instance of `InvalidPayloadOffsetError`.
    ///
    /// - Parameters:
    ///    - offset: The offset that was requested.
    ///    - availableBytes: The number of bytes available in the file at the time of the request.
    ///
    public init(offset: UInt64, availableBytes: Int) {
        self.offset = offset
        self.availableBytes = availableBytes
    }
}
