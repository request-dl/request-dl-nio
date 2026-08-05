//
// See LICENSE for this package's licensing information.
//

private struct PayloadChunkSizeKey: RequestEnvironmentKey {
    static var defaultValue: Int? { nil }
}

extension RequestEnvironmentValues {

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
}
