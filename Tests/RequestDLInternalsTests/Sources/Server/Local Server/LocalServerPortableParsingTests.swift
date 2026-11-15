//
// See LICENSE for this package's licensing information.
//

// The Network.framework server only exists where `NIOCore` does not (see `LocalServer
// .PortableServer`), so this is only built there: the build with the `NIOTransport` trait off.
#if !canImport(NIOCore)

import Testing

@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// What the hand-rolled HTTP/1.1 server makes of the bytes a client sends.
///
/// `parseRequest` answers `nil` for "more data is needed", so a head it cannot decode is not an
/// error the test sees: the request is simply never answered, and the client waits until its read
/// timeout. These go through the parser itself, with the bytes `URLSession` puts on the wire.
struct LocalServerPortableParsingTests {

    private typealias Connection = LocalServer.PortableServer.Connection

    private func request(headerLine: [UInt8]) -> [UInt8] {
        Array("GET /path HTTP/1.1\r\nHost: localhost\r\n".utf8)
            + headerLine
            + Array("\r\n\r\n".utf8)
    }

    @Test
    func parseRequest_whenAHeaderValueIsLatin1_readsTheRequest() throws {
        // Given: `URLSession` sends "José" as ISO Latin-1, `é` being the single byte 0xE9, which is
        // not valid UTF-8.
        let bytes = request(headerLine: Array("X-A: Jos".utf8) + [0xE9])

        // When
        let parsed = try #require(Connection.parseRequest(from: bytes))

        // Then
        #expect(parsed.consumed == bytes.count)
        #expect(parsed.head.uri == "/path")
        #expect(parsed.head.headers.first { $0.name == "X-A" }?.value == "José")
    }

    @Test
    func parseRequest_whenAHeaderValueIsUTF8_readsTheRequest() throws {
        // Given: the bytes `.nio` sends for the same value.
        let bytes = request(headerLine: Array("X-A: José".utf8))

        // When
        let parsed = try #require(Connection.parseRequest(from: bytes))

        // Then
        #expect(parsed.head.headers.first { $0.name == "X-A" }?.value == "José")
    }

    @Test
    func parseRequest_whenTheHeadIsNotComplete_waitsForMoreData() {
        // Given
        let bytes = Array("GET /path HTTP/1.1\r\nX-A: Jos".utf8) + [0xE9]

        // Then
        #expect(Connection.parseRequest(from: bytes) == nil)
    }
}

#endif
