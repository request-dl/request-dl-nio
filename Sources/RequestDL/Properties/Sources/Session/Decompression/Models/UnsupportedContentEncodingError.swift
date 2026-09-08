//
// See LICENSE for this package's licensing information.
//

/// Thrown when a response's `Content-Encoding` matches none of the algorithms passed to
/// ``Session/decompressionAlgorithms(_:limit:)``.
///
/// Only reachable once RequestDL has already taken over `Accept-Encoding` itself (any
/// non-native algorithm in the list, or `.disabled`'s own `identity` override) -- a server is
/// free to ignore what it was asked for, and this is what surfaces that rather than silently
/// handing back undecoded bytes as if they were plain text.
public struct UnsupportedContentEncodingError: Error, Sendable {

    /// The `Content-Encoding` value the response actually carried.
    public let value: String
}

// MARK: - CustomStringConvertible

extension UnsupportedContentEncodingError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL received a response encoded as "\(value)", which doesn't match any algorithm \
        passed to .decompressionAlgorithms(_:limit:). Add a Decompressor for "\(value)", or \
        catch this error and read the raw compressed bytes yourself.
        """
    }
}
