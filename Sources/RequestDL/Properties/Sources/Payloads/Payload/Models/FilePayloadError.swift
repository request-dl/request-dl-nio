//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import RequestDLInternals
#endif

/// An error thrown when RequestDL cannot read the file behind a `Form` or `Payload` file upload.
///
/// `Form(name:filename:contentType:url:)` and `Payload(url:contentType:)` both stream their body
/// from disk through a file backed buffer that, by design, treats a missing or unreadable file
/// as an empty one rather than failing — see `Internals.Buffer`. Left unchecked that turns a
/// wrong `url` into a request sent with a silently empty body instead of an error anywhere near
/// the mistake. This type exists to fail loudly instead, before that buffer is ever built.
public struct FilePayloadError: Error, Sendable {

    /// The specific reason the file could not be read.
    public enum Context: Sendable {
        /// No file exists at ``url``.
        case notFound

        /// A file exists at ``url``, but the file system refused to report on it — most often a
        /// permissions problem.
        case cantAccessFile(reason: any Error)
    }

    // MARK: - Public properties

    /// The file `URL` that could not be read.
    public let url: URL

    /// The reason it could not be read.
    public let context: Context

    // MARK: - Inits

    init(url: URL, context: Context) {
        self.url = url
        self.context = context
    }
}

// MARK: - CustomStringConvertible

extension FilePayloadError: CustomStringConvertible {

    public var description: String {
        let path = url.absolutePath(percentEncoded: false)

        switch context {
        case .notFound:
            return """
                RequestDL couldn't read the file at "\(path)" for this Form/Payload upload: no \
                file exists there.

                Without this check, the request would have gone out with a silently empty body \
                instead of the file's contents — a missing file has no error of its own to \
                surface through the upload path. Double check how this URL was built: a file \
                that ships inside your app bundle needs `Bundle.main.url(forResource:withExtension:)` \
                (or the target's own resource bundle), not a path assembled by hand.
                """
        case .cantAccessFile(let reason):
            return """
                RequestDL couldn't read the file at "\(path)" for this Form/Payload upload: \(reason)
                """
        }
    }
}
