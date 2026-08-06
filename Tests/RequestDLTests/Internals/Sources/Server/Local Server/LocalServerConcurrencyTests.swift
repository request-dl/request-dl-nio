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
// must not see each other's responses or hang. On a visionOS CI run under heavy shared-runner
// contention, this test's own 200 concurrently-connecting sessions have themselves hit
// `HTTPClientError.connectTimeout` at this shared group, in addition to the InternalsSessionTests
// timeout described below — on this machine even a single server thread clears 200 concurrent
// connections in well under a second, so the elapsed-time assertion below is only a "didn't hang"
// sanity check, not a guard against either regression. The real mitigation for both is the thread
// count on `LocalServer.ServerManager.shared` (bumped 1→4, then 4→8 — see LocalServer.swift);
// verifying either bump actually holds requires the real visionOS Simulator CI environment.
struct LocalServerConcurrencyTests {

    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
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
        // it clears in well under a second regardless of server thread count. 30s was too tight
        // for heavily-loaded shared CI runners (observed up to ~60s on visionOS with all 200
        // sessions still resolving correctly); 180s keeps this a hang-canary without being a
        // performance assertion.
        #expect(elapsed < .seconds(180))
    }
}
