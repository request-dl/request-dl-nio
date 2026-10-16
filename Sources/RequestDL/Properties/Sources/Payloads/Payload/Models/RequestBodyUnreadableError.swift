//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A part of the request body could not be read while it was being sent.
///
/// The body is assembled before the request goes out, and a file that backs it can be removed,
/// replaced or cut short in between. Going on without the part would send a body shorter than the
/// length declared for it, so the request fails instead and nothing more of it is sent.
public struct RequestBodyUnreadableError: Error, Sendable, Hashable, CustomStringConvertible {

    /// How many bytes the part had said it could still give.
    public let expectedBytes: Int

    public var description: String {
        """
        A part of the request body could not be read while it was being sent: it reported \
        \(expectedBytes) readable bytes and gave none. A file that backs the body was likely \
        removed or changed after the body was assembled.
        """
    }

    init(expectedBytes: Int) {
        self.expectedBytes = expectedBytes
    }

    init(_ error: Internals.RequestBodyPartUnreadableError) {
        self.init(expectedBytes: error.expectedBytes)
    }
}
