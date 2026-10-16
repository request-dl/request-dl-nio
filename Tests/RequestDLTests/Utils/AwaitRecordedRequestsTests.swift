//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// ``awaitRecordedRequests(_:atLeast:timeout:matching:)`` is what every test that reads what the
/// server recorded waits with, so what it says when the wait ends matters as much as that it waits:
/// a CI log that only says a condition was unmet cannot tell a request that never came from one
/// that came different.
struct AwaitRecordedRequestsTests {

    private func get(_ path: String, from server: TransferServer, range: String? = nil) async throws {
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path(path)

            if let range {
                CustomHeader(name: "Range", value: range)
            }
        }
        .result()
    }

    @Test
    func whenTheServerRecordedEnough_returns() async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            try await get("/resource", from: server)

            // Then
            try await awaitRecordedRequests(server)
        }
    }

    @Test
    func whenTheServerRecordedNothing_failsSayingSo() async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Then
            let error = try await #require(throws: RecordedRequestsTimeoutError.self) {
                try await awaitRecordedRequests(server, atLeast: 1, timeout: 0.2)
            }

            #expect(error.expected == 1)
            #expect(error.recorded.isEmpty)
        }
    }

    /// The requests it did record come with the failure: how many and what they were.
    @Test
    func whenTheServerRecordedTooFew_failsWithWhatItRecorded() async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            try await get("/resource", from: server)
            try await awaitRecordedRequests(server)

            // Then
            let error = try await #require(throws: RecordedRequestsTimeoutError.self) {
                try await awaitRecordedRequests(server, atLeast: 2, timeout: 0.2)
            }

            #expect(error.expected == 2)
            #expect(error.recorded.count == 1)
            #expect(error.recorded.first?.contains("GET /resource") == true)
            #expect(String(describing: error).contains("GET /resource"))
        }
    }

    /// Only the requests the predicate accepts are counted; the others are still reported.
    @Test
    func whenGivenAPredicate_countsOnlyTheRequestsItAccepts() async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: one request with a `Range` and one without.
            try await get("/resource", from: server)
            try await get("/resource", from: server, range: "bytes=10-")
            try await awaitRecordedRequests(server, atLeast: 2)

            // Then
            try await awaitRecordedRequests(server) { $0.header("Range") != nil }

            let error = try await #require(throws: RecordedRequestsTimeoutError.self) {
                try await awaitRecordedRequests(server, atLeast: 2, timeout: 0.2) { $0.header("Range") != nil }
            }

            #expect(error.recorded.count == 2)
            #expect(error.recorded.contains { $0.contains("range=bytes=10-") })
        }
    }
}
