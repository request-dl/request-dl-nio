//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// One part of a `multipart/form-data` body: its headers and its bytes.
struct FormItem: Sendable {

    struct Output {

        let name: String
        let filename: String?
        let headers: HTTPHeaders
        let buffer: Internals.AnyBuffer
    }

    // MARK: - Private properties

    private let name: String
    private let filename: String?
    private let additionalHeaders: HTTPHeaders?
    private let charset: Charset
    private let urlEncoder: URLEncoder
    private let factory: PayloadFactory

    // MARK: - Inits

    init(
        name: String,
        filename: String?,
        additionalHeaders: HTTPHeaders?,
        charset: Charset,
        urlEncoder: URLEncoder,
        factory: PayloadFactory
    ) {
        self.name = name
        self.filename = filename
        self.additionalHeaders = additionalHeaders
        self.charset = charset
        self.urlEncoder = urlEncoder
        self.factory = factory
    }

    // MARK: - Internal methods

    /// Runs the factory and turns whatever it produced into a part.
    ///
    /// - Note: `method` is `nil` because a form part has no HTTP method of its own. Only the
    /// top level payload consults it, to decide between a query string and a body.
    ///
    /// - Note: `payloadEncoder` is `nil` because `Form` has no `PayloadEncoder`-based
    /// initializer — none of its factories ever read it.
    func callAsFunction() async throws -> Output {
        let output = try await factory(
            .init(
                method: nil,
                charset: charset,
                urlEncoder: urlEncoder,
                payloadEncoder: nil
            )
        )

        switch output.source {
        case .buffer(let buffer):
            return .init(
                name: name,
                filename: filename,
                headers: makeHeader(buffer, for: output.contentType),
                buffer: buffer
            )

        case .urlEncoded(let queries):
            let data = try charset.encode(queries.joined())
            let buffer = await Internals.DataBuffer(data)

            return .init(
                name: name,
                filename: filename,
                headers: makeHeader(buffer, for: output.contentType),
                buffer: buffer
            )
        }
    }

    // MARK: - Private methods

    private func makeHeader(
        _ buffer: Internals.AnyBuffer,
        for contentType: ContentType
    ) -> HTTPHeaders {
        var headers = HTTPHeaders()

        headers.set(name: "Content-Disposition", value: contentDisposition())
        headers.set(name: "Content-Type", value: String(contentType))
        // `readableBytes`, not `estimatedBytes`. The estimate is the size of the whole backing
        // store, while what goes on the wire is what the cursor can still read — a partially
        // read buffer would otherwise declare a part longer than it sends. It is also arithmetic
        // rather than a stat call, which for a file backed part would cost one syscall per part.
        headers.set(name: "Content-Length", value: String(buffer.readableBytes))

        if let additionalHeaders {
            // The caller's headers win.
            //
            // - Important: Must not be `{ lhs, _ in lhs }`, which keeps the receiver — the
            // receiver here is the set generated just above, so that closure would silently
            // discard a caller's custom `Content-Type` on a part, leaving the `headers:` closure
            // on `Form` with no way to override anything this method touches.
            //
            // Assumes `HTTPHeaders.merging(_:uniquingKeysWith:)` passes the receiver's value
            // first, as `Dictionary` does. Worth a glance at the declaration.
            headers = headers.merging(additionalHeaders) { _, caller in caller }
        }

        return headers
    }

    private func contentDisposition() -> String {
        var contentDisposition = "form-data; name=\"\(Self.escapedParameterValue(name))\""

        if let filename {
            contentDisposition += "; filename=\"\(Self.escapedParameterValue(filename))\""
        }

        return contentDisposition
    }

    /// Percent-encodes the characters that would otherwise let `name`/`filename` -- often
    /// sourced from a URL's `lastPathComponent`, i.e. attacker-influenced -- break out of this
    /// quoted-string and inject an extra header or a whole extra part into the body. `"` ends
    /// the quoted-string early; a bare CR or LF ends the header line early, since these are body
    /// bytes handed straight to the wire with no header-line validation downstream. Matches the
    /// convention curl and browsers use for `multipart/form-data` (see the WHATWG HTML living
    /// standard's "multipart/form-data" algorithm).
    ///
    /// - Important: Walks `unicodeScalars`, not `Character`s -- a literal CRLF pair is one
    /// `Character` (a single extended grapheme cluster) in Swift, so matching against the
    /// `Character` values `"\r"`/`"\n"` would silently miss it and let the pair straight through.
    private static func escapedParameterValue(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.unicodeScalars.count)

        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                escaped += "%22"
            case "\r":
                escaped += "%0D"
            case "\n":
                escaped += "%0A"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }
}
