/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PayloadFactory: Sendable {

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput
}

struct PayloadInput {

    let method: String?
    let charset: Charset
    let urlEncoder: URLEncoder

    func jsonObject(_ array: [Any], contentType: ContentType) throws -> PayloadOutput {
        .init(
            contentType: .init(String(contentType) + "; charset=\(charset)"),
            source: try .urlEncoded(array.enumerated().reduce([]) {
                try $0 + urlEncoder.encode($1.element, forKey: String($1.offset))
            })
        )
    }

    func jsonObject(_ dictionary: [AnyHashable: Any], contentType: ContentType) throws -> PayloadOutput {
        .init(
            contentType: .init(String(contentType) + "; charset=\(charset)"),
            source: try .urlEncoded(dictionary.reduce([]) {
                try $0 + urlEncoder.encode($1.value, forKey: String(describing: $1.key))
            })
        )
    }
}

struct PayloadOutput {

    enum Source {
        case buffer(Internals.AnyBuffer)
        case urlEncoded([QueryItem])
    }

    let contentType: ContentType
    let source: Source
}
