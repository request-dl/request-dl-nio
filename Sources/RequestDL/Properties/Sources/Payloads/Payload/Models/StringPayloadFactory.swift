/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput {
        try .init(
            contentType: .init(String(contentType) + "; charset=\(input.charset)"),
            source: .buffer(Internals.DataBuffer(input.charset.encode(verbatim)))
        )
    }
}
