//
// See LICENSE for this package's licensing information.
//

/// An error thrown by ``Property/compression(_:onDuplicateHeader:shouldCompressBodyData:)`` when
/// the request already carries a `Content-Encoding` header and ``CompressionDuplicateHeaderBehavior``
/// is left at its default, ``CompressionDuplicateHeaderBehavior/error``.
public struct DuplicateContentEncodingError: Error, Sendable {

    /// The `Content-Encoding` value the request already carried.
    public let value: String
}

// MARK: - CustomStringConvertible

extension DuplicateContentEncodingError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL could not enable request-body compression because a `Content-Encoding` header \
        ("\(value)") is already set on this request. If the body is already compressed, pass \
        `.skip` to .compression(_:onDuplicateHeader:) to send it as it is. If the header is \
        stale and the body is not compressed, pass `.replace`, or remove the existing header.
        """
    }
}
