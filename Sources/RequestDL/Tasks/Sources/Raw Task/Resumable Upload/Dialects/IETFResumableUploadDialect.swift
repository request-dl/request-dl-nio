//
// See LICENSE for this package's licensing information.
//

/// The resumable upload of the IETF HTTP working group
/// (`draft-ietf-httpbis-resumable-upload`, written against revision 12), in the form its section
/// on careful upload creation describes.
///
/// Careful creation is the one that needs nothing but ordinary requests and responses: the
/// optimistic one learns the upload's URL from a `104` informational response, which neither
/// executor hands over. Here the client already knows the resource takes resumable uploads, creates
/// the upload with no body, gets the URL back in a regular response, and sends the body to it.
///
/// - The request the caller wrote becomes the one that creates the upload, with
///   `Upload-Complete: ?0` and no body. The server answers it with the upload's URL.
/// - The body goes in a `PATCH` of `application/partial-upload` that states the offset it starts
///   from and, being the rest of the body, that it completes the upload.
/// - A `HEAD` of the upload says how much of it the server has.
/// - The response to the `PATCH` that completes the upload is the response to the whole request.
///
/// - Important: The draft is not an RFC and can still change. Nothing here is negotiated; it is
///   spoken only where the caller asked for it.
struct IETFResumableUploadDialect: ResumableUploadDialect {

    // MARK: - Internal properties

    var requiresKnownLength: Bool {
        false
    }

    // MARK: - Internal methods

    func creation(for request: RequestConfiguration, length: Int64?) -> RequestConfiguration {
        var configuration = request

        configuration.body = nil
        configuration.cachePolicy = []
        configuration.cacheStrategy = .ignoreCachedData
        configuration.compression = nil
        configuration.shouldCompressBodyData = nil

        configuration.headers.remove(name: "Content-Length")
        configuration.headers.remove(name: "Transfer-Encoding")
        configuration.headers.set(name: "Upload-Complete", value: "?0")

        if let length {
            configuration.headers.set(name: "Upload-Length", value: String(length))
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
        request.derived(method: "HEAD", url: resource.url)
    }

    func report(from head: ResponseHead) throws -> UploadOffsetReport {
        guard (200..<300).contains(head.status.code) else {
            throw ResumableUploadDialectError(reason: .offsetRejected(status: head.status.code))
        }

        guard let offset = head.headers.integer(for: "Upload-Offset") else {
            throw ResumableUploadDialectError(reason: .missingOffset)
        }

        return UploadOffsetReport(
            offset: offset,
            length: head.headers.integer(for: "Upload-Length"),
            isComplete: head.headers.boolean(for: "Upload-Complete") ?? false
        )
    }

    func append(
        to resource: UploadResource,
        from offset: Int64,
        like request: RequestConfiguration
    ) -> RequestConfiguration {
        var configuration = request.derived(method: "PATCH", url: resource.url)

        configuration.headers.set(name: "Content-Type", value: "application/partial-upload")
        configuration.headers.set(name: "Upload-Offset", value: String(offset))
        configuration.headers.set(name: "Upload-Complete", value: "?1")

        return configuration
    }

    func outcome(of head: ResponseHead, offset: Int64, length: Int64?) -> UploadAppendOutcome {
        switch head.status.code {
        case 409:
            return .conflict(offset: head.headers.integer(for: "Upload-Offset"))
        case 404, 410:
            return .gone
        case 200..<300:
            return .finished
        default:
            return .other
        }
    }

    func cancellation(of resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration? {
        request.derived(method: "DELETE", url: resource.url)
    }
}
