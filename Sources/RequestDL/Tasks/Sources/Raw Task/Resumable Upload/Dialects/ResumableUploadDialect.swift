//
// See LICENSE for this package's licensing information.
//

/// The upload a server created for a request, which is where the rest of the body is sent to.
@_spi(Private)
public struct UploadResource: Sendable, Hashable {

    /// Absolute URL of the upload.
    let url: String
}

/// What a server says about an upload it holds.
@_spi(Private)
public struct UploadOffsetReport: Sendable, Hashable {

    /// How many bytes of the body the server has.
    let offset: Int64

    /// How long the whole body is, when the server says.
    let length: Int64?

    /// Whether the server considers the upload finished.
    let isComplete: Bool
}

/// What the response to sending the rest of a body means.
@_spi(Private)
public enum UploadAppendOutcome: Sendable, Hashable {

    /// The server has the whole body. The response is the response of the upload as a whole.
    case finished

    /// The server took part of the body and holds `offset` bytes now: more is still to be sent.
    case partial(offset: Int64)

    /// The server holds another number of bytes than the offset that was sent from. The offset is
    /// the server's, when it says.
    case conflict(offset: Int64?)

    /// The server no longer has the upload, so there is nothing to continue.
    case gone

    /// Anything else. A response that is not about resuming at all, so it goes to the caller as
    /// the response of the request.
    case other
}

/// Why a response was not what a dialect needs from it.
@_spi(Private)
public struct ResumableUploadDialectError: Error, Hashable {

    enum Reason: Sendable, Hashable {

        /// The response to creating the upload is not a success.
        case creationRejected(status: UInt)

        /// The response to creating the upload has no usable `Location`.
        case missingLocation

        /// The response to asking for the offset is not a success.
        case offsetRejected(status: UInt)

        /// The response to asking for the offset has no valid offset.
        case missingOffset
    }

    let reason: Reason
}

/// How one resumable upload protocol is spoken: the requests it takes and what its responses
/// mean, and nothing else.
///
/// A dialect does no I/O and keeps no state. Deciding when to create, ask, send again, give up or
/// start over is the same for every protocol and belongs to whoever drives it; a protocol only
/// differs in which request does each of those and which response means what. That is why the
/// IETF draft and tus fit the same shape, and a third could.
///
/// Every request is built from the request the caller wrote, so what the caller set up for it
/// (credentials, cookies, a proxy) reaches the requests that finish the job.
@_spi(Private)
public protocol ResumableUploadDialect: Sendable {

    /// Whether the length of the body has to be declared before its first byte.
    var requiresKnownLength: Bool { get }

    /// The request that creates the upload, with no body.
    func creation(for request: RequestConfiguration, length: Int64?) -> RequestConfiguration

    /// The upload a successful response to ``creation(for:length:)`` created.
    func resource(from head: ResponseHead, createdFor request: RequestConfiguration) throws -> UploadResource

    /// The request that asks how much of the upload the server has.
    func offsetQuery(for resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration

    /// What the response to ``offsetQuery(for:like:)`` says.
    func report(from head: ResponseHead) throws -> UploadOffsetReport

    /// The request that sends the body from `offset` to the end, without a body: the caller gives
    /// it the bytes.
    func append(
        to resource: UploadResource,
        from offset: Int64,
        like request: RequestConfiguration
    ) -> RequestConfiguration

    /// What the response to ``append(to:from:like:)`` means, given the offset it was sent from and
    /// how long the whole body is.
    func outcome(of head: ResponseHead, offset: Int64, length: Int64?) -> UploadAppendOutcome

    /// The response to hand over as the response of the upload, when the server holds all of it but
    /// the response to the request that completed it was lost, and `head` is what the server just
    /// said about the upload. `nil` when nothing the server says takes the place of that response,
    /// as when it is the response of the application.
    func completionResponse(from head: ResponseHead) -> ResponseHead?

    /// The request that tells the server the upload is abandoned, if the protocol has one.
    func cancellation(of resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration?
}
