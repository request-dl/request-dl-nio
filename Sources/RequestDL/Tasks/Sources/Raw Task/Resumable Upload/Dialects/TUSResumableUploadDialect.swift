//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Data
#else
import struct Foundation.Data
#endif

/// The tus resumable upload protocol, version 1.0.0, with its creation extension.
///
/// - The upload is created by a `POST` to the URL of the request that was written, declaring the
///   length of the body, and the server answers with the URL of the upload.
/// - The body goes in a `PATCH` of `application/offset+octet-stream` that states the offset it
///   starts from.
/// - A `HEAD` of the upload says how much of it the server has.
///
/// What differs from the IETF draft is what the request that was written means. Here it only says
/// where the endpoint is and what to authenticate with: the method is replaced by the `POST` that
/// tus defines, and the response to the whole upload is the one to the last `PATCH`, which tus
/// leaves without a body, not a response of the application. A `Content-Type` is carried over as
/// the `filetype` of the upload's metadata, since tus has no other place for it.
///
/// The length is always declared when the upload is created. The extension that defers it is not
/// used.
struct TUSResumableUploadDialect: ResumableUploadDialect {

    // MARK: - Private static properties

    private static let version = "1.0.0"

    // MARK: - Internal properties

    var requiresKnownLength: Bool {
        true
    }

    // MARK: - Internal methods

    func creation(for request: RequestConfiguration, length: Int64?) -> RequestConfiguration {
        precondition(length != nil, "tus declares the length of the upload when it is created")

        var configuration = request.derived(method: "POST", url: request.url)

        configuration.headers.set(name: "Tus-Resumable", value: Self.version)
        configuration.headers.set(name: "Upload-Length", value: String(length ?? .zero))

        if let contentType = request.headers.first(name: "Content-Type") {
            let encoded = Data(contentType.utf8).base64EncodedString()
            configuration.headers.set(name: "Upload-Metadata", value: "filetype \(encoded)")
        }

        return configuration
    }

    func resource(from head: ResponseHead, createdFor request: RequestConfiguration) throws -> UploadResource {
        guard (200..<300).contains(head.status.code) else {
            throw ResumableUploadDialectError(reason: .creationRejected(status: head.status.code))
        }

        guard
            let location = head.headers.first(name: "Location"),
            let url = request.resolving(location: location)
        else {
            throw ResumableUploadDialectError(reason: .missingLocation)
        }

        return UploadResource(url: url)
    }

    func offsetQuery(for resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration {
        var configuration = request.derived(method: "HEAD", url: resource.url)
        configuration.headers.set(name: "Tus-Resumable", value: Self.version)
        return configuration
    }

    func report(from head: ResponseHead) throws -> UploadOffsetReport {
        guard (200..<300).contains(head.status.code) else {
            throw ResumableUploadDialectError(reason: .offsetRejected(status: head.status.code))
        }

        guard let offset = head.headers.integer(for: "Upload-Offset") else {
            throw ResumableUploadDialectError(reason: .missingOffset)
        }

        let length = head.headers.integer(for: "Upload-Length")

        return UploadOffsetReport(
            offset: offset,
            length: length,
            isComplete: length.map { offset >= $0 } ?? false
        )
    }

    func append(
        to resource: UploadResource,
        from offset: Int64,
        like request: RequestConfiguration
    ) -> RequestConfiguration {
        var configuration = request.derived(method: "PATCH", url: resource.url)

        configuration.headers.set(name: "Tus-Resumable", value: Self.version)
        configuration.headers.set(name: "Content-Type", value: "application/offset+octet-stream")
        configuration.headers.set(name: "Upload-Offset", value: String(offset))

        return configuration
    }

    func outcome(of head: ResponseHead, offset: Int64, length: Int64?) -> UploadAppendOutcome {
        switch head.status.code {
        case 409:
            // tus does not say which offset the server holds in the answer: it is asked for.
            return .conflict(offset: nil)
        case 403, 404, 410:
            return .gone
        case 200..<300:
            guard let held = head.headers.integer(for: "Upload-Offset") else {
                return .other
            }

            if let length, held < length {
                return .partial(offset: held)
            }

            return .finished
        default:
            return .other
        }
    }

    func completionResponse(from head: ResponseHead) -> ResponseHead? {
        // What tus answers to the `PATCH` that completes an upload carries nothing but the offset,
        // which is also what the answer to asking for it says.
        head
    }

    func cancellation(of resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration? {
        var configuration = request.derived(method: "DELETE", url: resource.url)
        configuration.headers.set(name: "Tus-Resumable", value: Self.version)
        return configuration
    }
}
