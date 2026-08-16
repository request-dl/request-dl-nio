//
// See LICENSE for this package's licensing information.
//

/// Turns a source value into the bytes of a request body, plus the content type describing them.
///
/// ## When to declare a charset
///
/// A factory adds `charset` to its content type when, and only when, it used
/// ``PayloadInput/charset`` to produce the bytes. Across the current factories that means:
///
/// - `StringPayloadFactory` encodes through the charset, so it declares it.
/// - The form-urlencoded paths encode the joined query through the charset, so they declare it.
/// - `JSONPayloadFactory` and `EncodablePayloadFactory` on their JSON paths do not: both
///   `JSONSerialization` and `JSONEncoder` always emit UTF-8, whatever the input says.
/// - `DataPayloadFactory` and `FilePayloadFactory` carry opaque bytes they did not produce.
///
/// The reason is that the header is a claim about the body. Declaring the requested charset on
/// a JSON payload would announce, say, ISO-8859-1 over bytes that are UTF-8, and a peer that
/// believed the header would decode garbage. Omitting it is a weaker claim; stating the wrong
/// one is a false claim, which is worse.
///
/// A consequence worth knowing: `.charset(_:)` has no effect on JSON payloads, by design.
import RequestDLInternals

protocol PayloadFactory: Sendable {

    func callAsFunction(_ input: PayloadInput) async throws -> PayloadOutput
}

struct PayloadInput {

    let method: String?
    let charset: Charset
    let urlEncoder: URLEncoder
    let payloadEncoder: (any PayloadEncoder)?

    func jsonObject(_ array: [Any], contentType: ContentType) throws -> PayloadOutput {
        .init(
            contentType: contentType.appending(charset: charset),
            // `flatMap` rather than `reduce` with `+`: appending an array to an accumulator
            // reallocates on every element, which is quadratic in the number of fields.
            source: try .urlEncoded(
                array.enumerated().flatMap {
                    try urlEncoder.encode($1, forKey: String($0))
                }
            )
        )
    }

    func jsonObject(_ dictionary: [AnyHashable: Any], contentType: ContentType) throws -> PayloadOutput {
        .init(
            contentType: contentType.appending(charset: charset),
            // Sorted by key. `Dictionary` iteration order depends on a hash seed that is
            // randomised per process, so the same payload produced a different field order on
            // every launch. For a GET these fields become the URL query, and the URL is the
            // cache key, so the disk cache could only ever hit within a single session and
            // missed every time the app was relaunched. It also broke any signature computed
            // over the encoded body.
            //
            // Ordering carries no meaning in form-urlencoded, so fixing it costs nothing.
            source: try .urlEncoded(
                dictionary
                    .map { (key: String(describing: $0.key), value: $0.value) }
                    .sorted { $0.key < $1.key }
                    .flatMap { try urlEncoder.encode($0.value, forKey: $0.key) }
            )
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
