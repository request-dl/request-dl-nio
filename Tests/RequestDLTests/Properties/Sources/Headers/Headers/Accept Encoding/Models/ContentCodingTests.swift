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
        let substring = "br gzip".split(separator: " ").first!

        // Then
        #expect(ContentCoding(substring) == "br")
    }

    @Test
    func descriptionReturnsTheRawValue() {
        #expect(ContentCoding.gzip.description == "gzip")
    }
}
