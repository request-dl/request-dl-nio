//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct DownloadResumptionPointTests {

    // MARK: - Helpers

    private func head(
        status: UInt = 200,
        _ headers: [(String, String)]
    ) -> ResponseHead {
        ResponseHead(
            url: URL(string: "https://example.com/file"),
            status: .init(code: status, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: HTTPHeaders(headers),
            isKeepAlive: true
        )
    }

    private func encoded(_ point: DownloadResumptionPoint) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(point), as: UTF8.self)
    }

    // MARK: - Eligibility

    @Test
    func aStrongEntityTag_makesAPoint() throws {
        let point = try #require(
            DownloadResumptionPoint(
                head: head([("ETag", "\"v1\""), ("Content-Length", "1000")]),
                offset: 250
            )
        )

        #expect(point.offset == 250)
        #expect(point.completeLength == 1_000)
        #expect(!point.isComplete)
    }

    @Test
    func aStrongLastModified_makesAPoint_whenNoEntityTagCompetesWithIt() {
        // The response is more than a second newer than the representation: strong.
        let point = DownloadResumptionPoint(
            head: head([
                ("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT"),
                ("Date", "Wed, 21 Oct 2015 07:28:05 GMT"),
            ]),
            offset: 0
        )

        #expect(point != nil)
    }

    @Test(
        arguments: [
            // A weak entity tag, and a missing validator: nothing a splice could be checked against.
            [("ETag", "W/\"v1\"")],
            [("Content-Length", "1000")],
            // `Last-Modified` in the same second as the response: could change without it changing.
            [("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT"), ("Date", "Wed, 21 Oct 2015 07:28:00 GMT")],
            // A content coding: offsets in it aren't offsets into what is received.
            [("ETag", "\"v1\""), ("Content-Encoding", "gzip")],
        ] as [[(String, String)]]
    )
    func aResponseThatCantBeContinuedSafely_makesNoPoint(headers: [(String, String)]) {
        #expect(DownloadResumptionPoint(head: head(headers), offset: 0) == nil)
    }

    @Test
    func aResponseThatIsNotAPlain200_makesNoPoint() {
        #expect(DownloadResumptionPoint(head: head(status: 206, [("ETag", "\"v1\"")]), offset: 0) == nil)
        #expect(DownloadResumptionPoint(head: head(status: 304, [("ETag", "\"v1\"")]), offset: 0) == nil)
    }

    @Test
    func aNegativeOffset_makesNoPoint() {
        #expect(DownloadResumptionPoint(head: head([("ETag", "\"v1\"")]), offset: -1) == nil)
    }

    // MARK: - Offset

    @Test
    func atOffset_keepsTheValidatorAndMovesTheOffset() throws {
        let point = try #require(DownloadResumptionPoint(head: head([("ETag", "\"v1\"")]), offset: 0))
        let moved = point.at(offset: 4_096)

        #expect(moved.offset == 4_096)
        #expect(moved.plan == point.plan)
        #expect(point.at(offset: -5).offset == 0)
    }

    @Test
    func isComplete_whenTheOffsetReachesTheLength() throws {
        let point = try #require(
            DownloadResumptionPoint(head: head([("ETag", "\"v1\""), ("Content-Length", "100")]), offset: 0)
        )

        #expect(!point.at(offset: 99).isComplete)
        #expect(point.at(offset: 100).isComplete)
        #expect(point.at(offset: 101).isComplete)
    }

    @Test
    func isNeverComplete_whenTheLengthIsNotKnown() throws {
        let point = try #require(DownloadResumptionPoint(head: head([("ETag", "\"v1\"")]), offset: 0))

        #expect(point.completeLength == nil)
        #expect(!point.at(offset: 10_000_000).isComplete)
    }

    // MARK: - Codable

    /// A point is kept across launches and across updates of the application, so what this writes
    /// is a format, not an implementation detail: a change here is a break for every stored point.
    @Test
    func theEncodedFormat_isStable() throws {
        let entityTag = try #require(
            DownloadResumptionPoint(
                head: head([("ETag", "\"abc\""), ("Content-Length", "1000")]),
                offset: 250
            )
        )

        #expect(
            try encoded(entityTag)
                == #"{"completeLength":1000,"offset":250,"validator":{"kind":"entityTag","value":"\"abc\""},"version":1}"#
        )

        let lastModified = try #require(
            DownloadResumptionPoint(
                head: head([
                    ("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT"),
                    ("Date", "Wed, 21 Oct 2015 07:28:05 GMT"),
                ]),
                offset: 0
            )
        )

        #expect(
            try encoded(lastModified)
                == #"{"offset":0,"validator":{"kind":"lastModified","value":"Wed, 21 Oct 2015 07:28:00 GMT"},"version":1}"#
        )
    }

    @Test
    func aPointSurvivesAnEncodeAndDecode() throws {
        let point = try #require(
            DownloadResumptionPoint(
                head: head([("ETag", "\"abc\""), ("Content-Length", "1000")]),
                offset: 250
            )
        )

        let decoded = try JSONDecoder().decode(DownloadResumptionPoint.self, from: JSONEncoder().encode(point))

        #expect(decoded == point)
        #expect(decoded.offset == 250)
        #expect(decoded.completeLength == 1_000)
    }

    @Test
    func aStoredPointFromTheFirstVersion_isReadBack() throws {
        let stored =
            #"{"completeLength":1000,"offset":250,"validator":{"kind":"entityTag","value":"\"abc\""},"version":1}"#

        let point = try JSONDecoder().decode(DownloadResumptionPoint.self, from: Data(stored.utf8))

        #expect(point.offset == 250)
        #expect(point.completeLength == 1_000)
    }

    @Test(
        arguments: [
            // A version this one doesn't know.
            #"{"offset":0,"validator":{"kind":"entityTag","value":"\"a\""},"version":2}"#,
            // Nonsense a corrupt store could hold.
            #"{"offset":-1,"validator":{"kind":"entityTag","value":"\"a\""},"version":1}"#,
            #"{"offset":0,"version":1}"#,
            #"{"offset":0,"validator":{"kind":"mystery","value":"x"},"version":1}"#,
            #"{"validator":{"kind":"entityTag","value":"\"a\""},"version":1}"#,
        ]
    )
    func aPointThatCantBeTrusted_failsToDecode(stored: String) {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(DownloadResumptionPoint.self, from: Data(stored.utf8))
        }
    }

    // MARK: - Error

    @Test
    func theError_describesItsReason() {
        let error = DownloadResumptionError(.representationChanged)

        #expect(error.reason == .representationChanged)
        #expect(error.description.contains("representationChanged"))
    }
}
