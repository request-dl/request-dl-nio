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

    /// Drains the body through its own portable `bytesSequence`, the same chunk-by-chunk
    /// iterator every executor's own streaming path already reads from, one `Internals.DataBuffer`
    /// per chunk.
    func buffers() async throws -> [Internals.DataBuffer] {
        var buffers = [Internals.DataBuffer]()

        for try await chunk in bytesSequence {
            var chunk = chunk
            buffers.append(await Internals.DataBuffer(chunk.asData()))
        }

        return buffers
    }
}
