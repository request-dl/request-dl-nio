/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Represents a step during the download process.
public struct DownloadStep: Sendable, Hashable {

    /// The response head.
    public let head: ResponseHead

    /// The downloaded bytes.
    public let bytes: AsyncBytes

    /// Initializes a new instance of `DownloadStep`.
    ///
    /// - Parameters:
    ///   - head: The response head.
    ///   - bytes: The downloaded bytes.
    public init(head: ResponseHead, bytes: AsyncBytes) {
        self.head = head
        self.bytes = bytes
    }
}
