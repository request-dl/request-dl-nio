//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A url-encoded `Payload`'s fields, held here until the whole property tree has finished
/// resolving.
///
/// `PayloadNode.make(_:)` cannot decide whether these fields belong in the URL's query string
/// or in the request body the moment it runs: that decision depends on the request's final HTTP
/// method (``PayloadNode/sendsFieldsAsQuery(_:)``), and nodes run in declaration order. A
/// `Payload` declared before a `RequestMethod(.post)` in the same property tree would otherwise
/// see `method == nil` at the point it runs -- indistinguishable from "no method configured at
/// all", which reads as query-string -- even though the method is about to become `POST`.
///
/// Deferring the whole decision to ``resolve(into:)``, run by `Resolve` only after every node in
/// the tree (including whichever `RequestMethod` wins) has contributed, mirrors how
/// `URLOverride`/`SystemProxy` resolution already defers to a final, complete
/// `RequestConfiguration` for the same reason.
struct PendingURLEncodedPayload: Sendable {

    // MARK: - Internal properties

    let queries: [QueryItem]
    let contentType: ContentType
    let charset: Charset
    let chunkSize: Int?
    let compression: (any Compressor)?
    let compressionDuplicateHeaderBehavior: CompressionDuplicateHeaderBehavior
    let shouldCompressBodyData: (@Sendable (Int) -> Bool)?

    // MARK: - Internal methods

    func resolve(into make: inout Make) async throws {
        guard !PayloadNode.sendsFieldsAsQuery(make.requestConfiguration.method) else {
            // Mirrors `PayloadNode`'s old `removeAnySetHeaders(_:)`: an earlier property (or an
            // earlier `Payload`, in the unusual case of more than one) may have already set
            // these for a body that these fields are, now that the final method is known, not
            // going to become.
            make.requestConfiguration.headers.remove(name: "Content-Type")
            make.requestConfiguration.headers.remove(name: "Content-Length")
            make.requestConfiguration.queries.append(contentsOf: queries)
            return
        }

        let buffer = try await Internals.DataBuffer(
            charset.encode(queries.joined())
        )

        PayloadNode.setBodyWithBuffer(
            buffer: buffer,
            contentType: contentType,
            chunkSize: chunkSize,
            compression: compression,
            compressionDuplicateHeaderBehavior: compressionDuplicateHeaderBehavior,
            shouldCompressBodyData: shouldCompressBodyData,
            make: &make
        )
    }
}
