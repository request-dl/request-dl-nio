//
// See LICENSE for this package's licensing information.
//

struct StringPayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let verbatim: String
    let contentType: ContentType

    // MARK: - Inits

    init<Verbatim: StringProtocol>(
        verbatim: Verbatim,
        contentType: ContentType = .text
    ) {
        self.verbatim = String(verbatim)
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput {
        try await .init(
            // Only adds a charset when the caller has not written one.
            contentType: contentType.appending(charset: input.charset),
            source: .buffer(Internals.DataBuffer(input.charset.encode(verbatim)))
        )
    }
}
