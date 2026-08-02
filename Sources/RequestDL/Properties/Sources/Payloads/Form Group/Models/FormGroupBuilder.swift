//
// See LICENSE for this package's licensing information.
//

/// Assembles a list of form items into the buffers of a `multipart/form-data` body.
struct FormGroupBuilder: Sendable {

    // MARK: - Internal properties

    /// The delimiter that separates parts, without the leading dashes.
    ///
    /// 128 random bits rendered as hex, which makes an accidental match with the payload
    /// negligible. It is not checked against the content, and cannot practically be.
    let boundary: String

    let items: [FormItem]

    // MARK: - Private properties

    /// The CRLF that separates multipart lines, per RFC 2046.
    ///
    /// A `String`, not a `Character`. CRLF really is a single extended grapheme cluster, so a
    /// `Character` holds it, but `Character` has no `utf8` view to write it out through, and
    /// the previous version reached for one in two places while interpolating into a `String`
    /// in a third. A `String` serves all three spellings and needs no argument.
    private let eol = "\r\n"

    // MARK: - Inits

    init(_ items: [FormItem]) {
        self.init(Self.makeBoundary(), items: items)
    }

    fileprivate init(_ boundary: String, items: [FormItem]) {
        self.boundary = boundary
        self.items = items
    }

    // MARK: - Private static methods

    /// - Note: A method, not a computed property. It returns something different on every call,
    /// and the previous `static var boundary` also shadowed the instance property of the same
    /// name, so which one a given line meant depended on where it sat.
    private static func makeBoundary() -> String {
        let prefix = UInt64.random(in: .min ... .max)
        let suffix = UInt64.random(in: .min ... .max)

        return "\(String(prefix, radix: 16)):\(String(suffix, radix: 16))"
    }

    // MARK: - Internal methods

    /// Produces the body, in order: a delimiter, headers and content per part, then the closing
    /// delimiter.
    func callAsFunction() async throws -> [Internals.AnyBuffer] {
        var buffers = [Internals.AnyBuffer]()

        for item in items {
            let delimiter = await Internals.DataBuffer("--\(boundary)\(eol)".utf8)
            let content = try await buildBuffer(item)
            let separator = await Internals.DataBuffer(eol.utf8)

            buffers.append(delimiter)
            buffers.append(contentsOf: content)
            buffers.append(separator)
        }

        // The closing delimiter carries trailing dashes and is followed by one CRLF.
        let closing = await Internals.DataBuffer("--\(boundary)--\(eol)".utf8)
        buffers.append(closing)

        return buffers
    }

    // MARK: - Private methods

    private func buildBuffer(_ item: FormItem) async throws -> [Internals.AnyBuffer] {
        let output = try await item()
        let headers = await buildHeadersBuffer(output.headers)

        return [headers, output.buffer]
    }

    /// The part headers, terminated by the blank line that separates them from the content.
    private func buildHeadersBuffer(_ headers: HTTPHeaders) async -> Internals.AnyBuffer {
        var buffer = await Internals.DataBuffer()

        for (name, value) in headers {
            await buffer.writeBytes("\(name): \(value)\(eol)".utf8)
        }

        await buffer.writeBytes(eol.utf8)
        return buffer
    }
}
