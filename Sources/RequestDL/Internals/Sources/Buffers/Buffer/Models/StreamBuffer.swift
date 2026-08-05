//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

/// A one directional cursor over a resource.
///
/// Two instances exist per store, one opened for reading and one for writing, and each keeps
/// its own offset. Neither is expected to be safe against concurrent use on its own: the
/// storage that owns them serializes seek and transfer into a single critical section.
///
/// - Note: The associated type is named `URL` and shadows `Foundation.URL` inside every
/// conforming type. Reaching the real one from there requires spelling out the module. Worth
/// renaming to `Address` or `Location` when there is appetite for the churn.
protocol StreamBuffer<URL>: Sendable {

    associatedtype URL: BufferURL

    /// The offset the next operation will address.
    var offset: UInt64 { get async throws }

    init(readingFrom url: URL) async throws
    init(writingTo url: URL) async throws

    /// Moves the offset. Positions past the end of the resource are legal.
    func seek(to offset: UInt64) async throws

    /// Writes every byte, advancing the offset by that count.
    func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async throws

    /// Reads up to `length` bytes, advancing the offset by however many arrived.
    /// - Returns: `nil` at the end of the resource.
    func readData(length: UInt64) async throws -> Data?

    func close() async throws
}
