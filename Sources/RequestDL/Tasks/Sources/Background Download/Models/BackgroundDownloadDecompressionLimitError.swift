//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

/// Reported through ``BackgroundDownloads/onEvent`` as a `.failed` event when the file a
/// ``BackgroundDownloadTask`` downloaded expands, once decoded, past the limit its session set
/// with ``Session/decompressionAlgorithms(_:limit:)``.
///
/// Decoding a background download is done by RequestDL when it has finished, for a
/// ``Decompressor`` of your own, and writes to the disk of the user. A ``DecompressionLimit`` that
/// was set bounds it as it bounds the native decoding of `.nio`; with ``DecompressionLimit/none``,
/// the default, the algorithm is its own to bound. What had been written is removed, and what was
/// at `destination` is left untouched.
public struct BackgroundDownloadDecompressionLimitError: Error, Sendable {

    /// The limit that was passed.
    public let limit: Session.DecompressionLimit
}

// MARK: - CustomStringConvertible

extension BackgroundDownloadDecompressionLimitError: CustomStringConvertible {

    public var description: String {
        switch limit {
        case .none:
            return "A background download expanded past a limit that was not set."
        case .size(let value):
            return "A background download expanded past \(value) bytes once decoded."
        case .ratio(let value):
            return "A background download expanded past \(value) times its size once decoded."
        }
    }
}

#endif
