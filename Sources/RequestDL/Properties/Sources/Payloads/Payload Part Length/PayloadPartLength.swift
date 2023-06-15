/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct PayloadChunkSizeKey: PropertyEnvironmentKey {
    static var defaultValue: Int?
}

extension PropertyEnvironmentValues {

    var payloadChunkSize: Int? {
        get { self[PayloadChunkSizeKey.self] }
        set { self[PayloadChunkSizeKey.self] = newValue }
    }
}

extension Property {

    /// Specifies the size of each body chunk in the payload during the upload process.
    ///
    /// - Parameter chunkSize: The desired size of each upload chunk.
    /// - Returns: A new instance of Property with the chunk size set.
    public func payloadChunkSize(_ chunkSize: Int) -> some Property {
        environment(\.payloadChunkSize, chunkSize)
    }

    /// Sets the length of payload parts to be used during the upload process.
    ///
    /// - Parameter length: The desired length of each payload part.
    /// - Returns: A new instance of Property with the payload part length set.
    @available(*, deprecated, renamed: "payloadChunkSize")
    public func payloadPartLength(_ length: Int) -> some Property {
        payloadChunkSize(length)
    }
}
