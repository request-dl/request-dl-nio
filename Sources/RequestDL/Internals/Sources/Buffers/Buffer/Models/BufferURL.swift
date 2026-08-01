//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.URL
#else
import struct Foundation.URL
#endif

protocol BufferURL: Sendable {

    static var temporaryURL: Self { get }

    /// Addresses a file system location, or `nil` when this kind of storage cannot.
    ///
    /// Replaces a runtime `Stream.self is FileStreamBuffer.Type` test. With the conversion
    /// declared per type, a third kind of storage has to say what it can address instead of
    /// silently falling into whichever branch happens to be last.
    static func make(from url: Foundation.URL) -> Self?

    /// Addresses an in memory location, or `nil` when this kind of storage cannot.
    static func make(from url: Internals.ByteURL) -> Self?

    /// Bytes currently in the resource.
    ///
    /// - Important: Not necessarily cheap. On a file system this is a stat call, so treat it
    /// as I/O rather than as a stored property.
    var writtenBytes: Int { get }

    func isResourceAvailable() -> Bool

    func createResourceIfNeeded()

    /// Drops every byte, releasing whatever the resource had grown to hold.
    func truncate()

    /// Removes the backing resource when this URL owns a temporary one.
    func removeIfTemporary()
}

extension BufferURL {

    static func make(from url: Foundation.URL) -> Self? {
        nil
    }

    static func make(from url: Internals.ByteURL) -> Self? {
        nil
    }

    func removeIfTemporary() {}
}
