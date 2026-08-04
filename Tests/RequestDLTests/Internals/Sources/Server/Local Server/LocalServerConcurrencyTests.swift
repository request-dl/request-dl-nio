//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

// `LocalServer.ServerManager.shared`'s server-side event loop group is a process-wide singleton
// shared by every LocalServer-backed suite (DataTaskTests, UploadTaskTests, InternalsSessionTests,
// ModifiersCollect*Tests, CachedRequestTests, ...), and swift-testing runs suites concurrently by
// default — so many independent sessions hit the same server/`ResponseQueue` at once in practice.
// This exercises that path directly: many concurrent sessions, each with its own uri/response slot,
// must not see each other's responses or hang. It does NOT reproduce the visionOS CI timeout itself
// (HTTPClientError.connectTimeout/.tlsHandshakeTimeout in InternalsSessionTests) — on this machine
// even a single server thread clears 200 concurrent connections in well under a second, so the
// elapsed-time assertion below is only a "didn't hang" sanity check, not a guard against that
// specific regression. The real fix for that bug is the thread count bump in LocalServer.swift;
// verifying it requires the actual visionOS Simulator CI environment.
struct LocalServerConcurrencyTests {

    @Test
    func manyConcurrentSessions_shareLocalServerWithoutCrossTalkOrHanging() async throws {
        let concurrency = 200
        let localServer = try await LocalServer(.standard)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateVerification = .some(.none)

        var mutableConfiguration = Internals.Session.Configuration()
        mutableConfiguration.secureConnection = secureConnection
        let configuration = mutableConfiguration

        let clock = ContinuousClock()
        let start = clock.now

        let resultCounts = try await withThrowingTaskGroup(of: Int.self) { group -> [Int] in
            for _ in 0..<concurrency {
                group.addTask {
                    let uri = "/" + UUID().uuidString
                    localServer.cleanup(at: uri)

                    let session = Internals.Session(
                        provider: .identified(
                            "com.requestdl.tests.local-server.concurrency.\(uri)",
                            numberOfThreads: 1
                        ),
                        configuration: configuration
                    )

                    var requestConfiguration = RequestConfiguration()
                    requestConfiguration.baseURL = "https://\(localServer.baseURL)"
                    requestConfiguration.pathComponents = [
                        uri.trimmingCharacters(in: .init(charactersIn: "/"))
                    ]

                    let task = try await session.execute(
                        requestConfiguration: requestConfiguration,
                        dataCache: .init(),
                        logger: nil
                    )

                    return try await Array(task()).count
                }
            }

            var counts = [Int]()
            for try await count in group {
                counts.append(count)
            }
            return counts
        }

        let elapsed = clock.now - start

        // Then
        #expect(resultCounts.count == concurrency)
        #expect(resultCounts.allSatisfy { $0 == 1 })

        // Sanity check only (see suite-level comment): this must not hang, but on a fast machine
        // it clears in well under a second regardless of server thread count.
        #expect(elapsed < .seconds(30))
    }
}
