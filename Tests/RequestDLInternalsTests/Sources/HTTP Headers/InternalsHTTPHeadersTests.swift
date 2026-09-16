//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsHTTPHeadersTests {

    @Test
    func httpHeaders_whenNameMatchesExactly_firstReturnsValue() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")

        // Then
        #expect(headers.first(name: "Content-Type") == "application/json")
    }

    @Test
    func httpHeaders_whenNameDiffersOnlyInCase_firstStillMatches() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")

        // Then
        #expect(headers.first(name: "content-type") == "application/json")
        #expect(headers.first(name: "CONTENT-TYPE") == "application/json")
        #expect(headers.first(name: "cOnTeNt-TyPe") == "application/json")
    }

    @Test
    func httpHeaders_whenNameAbsent_firstReturnsNil() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")

        // Then
        #expect(headers.first(name: "Authorization") == nil)
    }

    @Test
    func httpHeaders_whenMultipleValuesForName_firstReturnsTheFirstOneAdded() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "X-Trace", value: "first")
        headers.add(name: "x-trace", value: "second")

        // Then
        #expect(headers.first(name: "X-TRACE") == "first")
    }

    @Test
    func httpHeaders_whenNameLengthsDiffer_containsReturnsFalse() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "ETag", value: "abc")

        // Then
        #expect(!headers.contains(name: "ETags"))
        #expect(!headers.contains(name: "ETa"))
    }

    @Test
    func httpHeaders_whenNameMatchesCaseInsensitively_containsReturnsTrue() {
        // Given
        var headers = Internals.HTTPHeaders()
        headers.add(name: "ETag", value: "abc")

        // Then
        #expect(headers.contains(name: "etag"))
    }
}
