//
// See LICENSE for this package's licensing information.
//

/// An error thrown by ``Session/compression(_:onDuplicateHeader:)`` when the request already
/// carries a `Content-Encoding` header and ``Session/DuplicateHeaderBehavior`` is left at its
/// default, ``Session/DuplicateHeaderBehavior/error``.
public struct DuplicateContentEncodingError: Error, Sendable {

    /// The `Content-Encoding` value the request already carried.
    public let value: String
}

// MARK: - CustomStringConvertible

extension DuplicateContentEncodingError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL could not enable request-body compression because a `Content-Encoding` header \
        ("\(value)") is already set on this request. Pass `.replace` or `.skip` to \
        .compression(_:onDuplicateHeader:) to allow this, or remove the existing header.
        """
    }
}
