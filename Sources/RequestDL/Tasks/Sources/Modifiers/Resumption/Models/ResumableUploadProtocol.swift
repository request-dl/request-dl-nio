//
// See LICENSE for this package's licensing information.
//

/// A protocol for uploading a body in a way that can be continued, for
/// ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``:
/// ``IETFResumableUpload`` and ``TUSResumableUpload``.
///
/// They differ in what the request that was written means to the server and in what the server
/// answers, not in how an upload that is interrupted is carried on, so everything else (the
/// attempts, the suspension, the progress) works the same whichever is used.
///
/// Not something to conform to: what a protocol is made of is not part of the package's API.
public protocol ResumableUploadProtocol: Sendable {

    @_spi(Private)
    var dialect: any ResumableUploadDialect { get }
}

/// The resumable upload of the IETF HTTP working group, `draft-ietf-httpbis-resumable-upload`
/// (written against revision 12), in the form that needs nothing but ordinary requests and
/// responses (its section on careful upload creation).
///
/// The request that was written is the one that creates the upload, with no body: the server
/// answers it with where the upload is, and the body is sent to it, from wherever the server says
/// it stands. The response to the request that completes the upload is the response to the
/// request that was written.
///
/// - Important: The draft is not an RFC and can still change, and nothing is negotiated: the
///   server has to speak it, and it is only spoken where it is asked for. Experimental.
public struct IETFResumableUpload: ResumableUploadProtocol {

    @_spi(Private)
    public var dialect: any ResumableUploadDialect {
        IETFResumableUploadDialect()
    }

    /// Creates the protocol. See ``ResumableUploadProtocol/ietf``.
    public init() {}
}

/// The tus resumable upload protocol, version 1.0.0, with its creation extension.
///
/// The upload is created by a `POST` to the URL of the request that was written, whatever its
/// method, with the length of the body, and the body is sent to the upload the server answers with.
/// What the request that was written means is only where the endpoint is and what to authenticate
/// with: a `Content-Type` is carried as the `filetype` of the upload's metadata, and the response
/// to the request that completes the upload is tus's, which has no body, and not a response of the
/// application. The length of the body has to be known up front, so a body that is compressed as
/// it is sent (see ``Property/compression(_:onDuplicateHeader:shouldCompressBodyData:)``) is
/// compressed first, once, and what is sent is what that produced.
public struct TUSResumableUpload: ResumableUploadProtocol {

    @_spi(Private)
    public var dialect: any ResumableUploadDialect {
        TUSResumableUploadDialect()
    }

    /// Creates the protocol. See ``ResumableUploadProtocol/tus``.
    public init() {}
}

extension ResumableUploadProtocol where Self == IETFResumableUpload {

    /// The IETF working group's resumable upload (experimental). See ``IETFResumableUpload``.
    public static var ietf: IETFResumableUpload {
        IETFResumableUpload()
    }
}

extension ResumableUploadProtocol where Self == TUSResumableUpload {

    /// The tus 1.0 resumable upload. See ``TUSResumableUpload``.
    public static var tus: TUSResumableUpload {
        TUSResumableUpload()
    }
}
