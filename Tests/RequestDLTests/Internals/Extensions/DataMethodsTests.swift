//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

struct DataMethodsTests {

    @Test
    func emptyDataDescribesAsEmpty() {
        #expect(Data().safeLogDescription() == "<empty>")
    }

    @Test
    func shortValidTextIsReturnedAsIs() {
        #expect(Data("hello".utf8).safeLogDescription(maxLength: 500) == "hello")
    }

    @Test
    func longValidTextIsTruncatedWithEllipsis() {
        // 6 bytes: over `maxLength` so it truncates, but at or under `maxLength * 2` so it
        // doesn't take the "too large to display" shortcut instead.
        let data = Data(String(repeating: "a", count: 6).utf8)
        #expect(data.safeLogDescription(maxLength: 4) == "aaaa…")
    }

    @Test
    func invalidUTF8IsReportedAsBinary() {
        // Given
        // A lone continuation byte is not valid UTF-8 on its own, so decoding and re-encoding
        // it does not round-trip.
        let data = Data([0x80])

        // Then
        #expect(data.safeLogDescription() == "<binary data: 1 bytes>")
    }

    @Test
    func dataOverTwiceTheMaxLengthIsReportedBySizeAloneWithoutDecoding() {
        // Given
        let data = Data(repeating: 0x41, count: 1_001)

        // Then
        #expect(data.safeLogDescription(maxLength: 500) == "<data: 1001 bytes (too large to display)>")
    }
}
