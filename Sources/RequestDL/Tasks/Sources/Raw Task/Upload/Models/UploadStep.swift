/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Represents a step during the upload process.
public struct UploadStep: Sendable, Hashable {

    /// The size of each chunk during upload.
    public let chunkSize: Int

    /// The total size of the upload.
    public let totalSize: Int

    /// Initializes a new instance of `UploadStep`.
    ///
    /// - Parameters:
    ///   - chunkSize: The size of each chunk during upload.
    ///   - totalSize: The total size of the upload.
    public init(chunkSize: Int, totalSize: Int) {
        self.chunkSize = chunkSize
        self.totalSize = totalSize
    }
}
