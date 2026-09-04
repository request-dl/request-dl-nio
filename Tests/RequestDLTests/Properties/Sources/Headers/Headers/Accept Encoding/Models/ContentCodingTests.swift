//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct ContentCodingTests {

    @Test
    func gzipRawValue() {
        #expect(ContentCoding.gzip == "gzip")
    }

    @Test
    func deflateRawValue() {
        #expect(ContentCoding.deflate == "deflate")
    }

    @Test
    func brotliRawValue() {
        #expect(ContentCoding.brotli == "br")
    }

    @Test
    func identityRawValue() {
        #expect(ContentCoding.identity == "identity")
    }

    @Test
    func allRawValue() {
        #expect(ContentCoding.all == "*")
    }

    @Test
    func initAcceptsAnyStringProtocol() {
        // Given
        let substring = "zstd gzip".split(separator: " ").first!

        // Then
        #expect(ContentCoding(substring) == "zstd")
    }

    @Test
    func descriptionReturnsTheRawValue() {
        #expect(ContentCoding.gzip.description == "gzip")
    }
}
