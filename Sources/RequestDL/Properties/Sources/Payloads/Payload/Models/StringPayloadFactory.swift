/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct StringPayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let verbatim: String
    let encode: @Sendable (String) throws -> Data
    let contentType: ContentType?

    // MARK: - Inits

    init<Verbatim: StringProtocol, Encoding: StringEncoding>(
        verbatim: Verbatim,
        encoding: Encoding,
        contentType: ContentType = .text
    ) {
        self.verbatim = String(verbatim)
        self.encode = { try encoding.encode($0) }
        self.contentType = Self.charset(contentType, encoding: encoding.description)
    }

    // MARK: - Internal static methods

    static func charset(_ contentType: ContentType, encoding charset: String) -> ContentType {
        var components = String(contentType)
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let index = components.firstIndex(where: {
            $0.range(of: "charset=", options: .caseInsensitive)?.lowerBound == $0.startIndex
        })

        if let index {
            components[index] = "charset=\(charset)"
        } else {
            components.append("charset=\(charset)")
        }

        return .init(components.joined(separator: "; "))
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> Internals.AnyBuffer {
        try Internals.DataBuffer(encode(verbatim))
    }
}
