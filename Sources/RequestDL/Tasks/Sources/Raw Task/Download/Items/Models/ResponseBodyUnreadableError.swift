//
// See LICENSE for this package's licensing information.
//

/// A part of the response body, already received, could not be read back.
///
/// Received chunks are kept in memory and spill to the disk when there are too many to hold, and
/// what was written there can be removed or fail to read before the reader gets to it. Ending the
/// body at that point would look exactly like a response that finished, with the rest of it
/// silently missing, so the read fails instead.
public struct ResponseBodyUnreadableError: Error, Sendable, Hashable, CustomStringConvertible {

    public var description: String {
        "A part of the response body that had already been received could not be read back."
    }

    init() {}
}
