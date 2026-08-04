//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.URL
#endif

/// A location a ``StreamBuffer`` can open, on disk or in memory.
///
/// The two `make(from:)` factories are how a buffer discovers what its stream type can address,
/// instead of testing the concrete type at runtime. Both default to `nil`, so a conforming type
/// only implements the one it supports.
protocol BufferURL: Sendable {

    /// A location nothing else holds, to be removed once the storage over it goes away.
    static var temporaryURL: Self { get }

    /// Addresses a file system location, or `nil` when this kind of storage cannot.
    static func make(from url: URL) -> Self?

    /// Addresses an in memory location, or `nil` when this kind of storage cannot.
    static func make(from url: Internals.ByteURL) -> Self?

    /// Bytes currently in the resource.
    ///
    /// - Important: Not necessarily cheap. On a file system this is an async stat call,
    /// so treat it as I/O rather than as a stored property.
    var writtenBytes: Int { get async }

    func isResourceAvailable() async -> Bool

    /// Creates the resource, and anything it needs above it, when it is not already there.
    func createResourceIfNeeded() async

    /// Drops every byte, releasing whatever the resource had grown to hold.
    ///
    /// - Warning: Allowed to replace the resource rather than shorten it in place. Callers
    /// close their open streams first.
    func truncate() async

    /// Removes the backing resource when this URL owns a temporary one.
    func removeIfTemporary() async
}

extension BufferURL {

    static func make(from url: URL) -> Self? {
        nil
    }

    static func make(from url: Internals.ByteURL) -> Self? {
        nil
    }

    /// In memory resources are reclaimed by ARC, so there is nothing to remove.
    func removeIfTemporary() async {}
}
