//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

/// Reported through ``BackgroundDownloads/onEvent`` as a `.failed` event when a
/// ``BackgroundDownloadTask`` finished in a launch other than the one that scheduled it and the
/// ``Decompressor`` for its `Content-Encoding` was not registered in this one.
///
/// What a download keeps across a relaunch is text. A ``Decompressor`` is a value of your own
/// type, which can't be, so after a relaunch it is the app's job to hand it back, with
/// ``BackgroundDownloads/registerDecompressors(_:)``, early in every launch, before
/// ``BackgroundDownloads/handleEvents(forBackgroundURLSession:completionHandler:)``.
///
/// The downloaded file is not kept: it is encoded, so there is nothing at `destination` to put it
/// in without passing it off as the decoded one, and the system removes it when the callback
/// returns. Schedule the download again once the decompressor is registered.
public struct BackgroundDownloadMissingDecompressorError: Error, Sendable {

    /// The `Content-Encoding` the response carried.
    public let contentEncoding: String
}

// MARK: - CustomStringConvertible

extension BackgroundDownloadMissingDecompressorError: CustomStringConvertible {

    public var description: String {
        """
        A background download finished encoded as "\(contentEncoding)", and no Decompressor for \
        "\(contentEncoding)" is registered in this launch. Register it with \
        BackgroundDownloads.registerDecompressors(_:) early in every launch, and schedule the \
        download again.
        """
    }
}

#endif
