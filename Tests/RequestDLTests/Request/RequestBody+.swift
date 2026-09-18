//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension RequestBody {

    func data() async throws -> Data {
        try await buffers().resolveData().reduce(Data(), +)
    }

    /// Drains the body chunk by chunk, in the order `RequestBody`'s own `AsyncSequence`
    /// conformance produces them -- the same `bytesSequence` `Internals.StreamWriterSequence`
    /// reads from on the wire (`RequestBody.connect(writer:body:eventLoop:)`, `.nio`-only, tested
    /// directly by `RequestBodyTests`), so this preserves the exact same chunk boundaries every
    /// caller here actually cares about, without needing `AsyncHTTPClient`'s
    /// `HTTPClient.Body.StreamWriter` machinery just to observe them.
    func buffers() async throws -> [Internals.DataBuffer] {
        var buffers: [Internals.DataBuffer] = []

        for try await chunk in bytesSequence {
            let url = Internals.ByteURL()
            url.replace(with: chunk)
            buffers.append(await Internals.DataBuffer(url))
        }

        return buffers
    }
}
