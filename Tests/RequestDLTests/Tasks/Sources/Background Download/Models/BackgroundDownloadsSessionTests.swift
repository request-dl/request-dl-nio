//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// Covers `BackgroundDownloads.Session`'s `taskDescription` encoding directly, independent of any
/// real `URLSessionTask` -- this is what a delegate callback decodes after a relaunch, when
/// nothing else about the original request survives, so it needs to round-trip correctly on its
/// own merits, not just "happen to work" against whatever a live download produces.
struct BackgroundDownloadsSessionTests {

    @Test
    func encodeThenDecode_roundTripsIdAndDestination() async throws {
        // Given
        let id = "episode-42"
        let destination = URL(fileURLWithPath: "/tmp/episode-42.mp3")

        // When
        let encoded = try #require(BackgroundDownloads.Session.encode(id: id, destination: destination))
        let decoded = try #require(BackgroundDownloads.Session.decode(encoded))

        // Then
        #expect(decoded.id == id)
        #expect(decoded.destination == destination)
    }

    @Test
    func decode_whenTaskDescriptionIsNil_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.decode(nil) == nil)
    }

    @Test
    func decode_whenTaskDescriptionIsNotEncodedByThisType_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.decode("not a descriptor") == nil)
    }
}

#endif
