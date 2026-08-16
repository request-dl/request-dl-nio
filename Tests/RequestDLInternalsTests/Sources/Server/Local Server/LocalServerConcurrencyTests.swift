//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

// This exercises many concurrent sessions, each with its own uri/response slot, and asserts they
// must not see each other's responses or hang. It deliberately drives 200 concurrently-connecting
// client sessions at once, so it runs against its own dedicated server/event loop group
// (`Configuration.stress` / `ServerManager.stress`, see LocalServer.swift and
// LocalServer.Configuration.swift) instead of `.standard`, which every other LocalServer-backed
// suite (DataTaskTests, UploadTaskTests, InternalsSessionTests, ModifiersCollect*Tests,
// CachedRequestTests, ...) shares — swift-testing runs suites concurrently by default, and this
// test's own burst previously starved those suites (and itself) into `HTTPClientError
// .connectTimeout` when it shared their group (ci-triage/TASKS.md T1b). `configuration.timeout
// .connect` below is also widened past AsyncHTTPClient's 10s default for the same reason: even on
// its own dedicated group, 200 simultaneous TLS handshakes under heavy CI contention can
// legitimately take longer than that.
struct LocalServerConcurrencyTests {

    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func manyConcurrentSessions_shareLocalServerWithoutCrossTalkOrHanging() async throws {
        let concurrency = 200
        let localServer = try await LocalServer(.stress, manager: .stress)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateVerification = .some(.none)

        var mutableConfiguration = Internals.Session.Configuration()
        mutableConfiguration.secureConnection = secureConnection
        mutableConfiguration.timeout.connect = 60_000_000_000
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

                    let client = try await session.client()

                    let request = try HTTPClient.Request(
                        url: "https://\(localServer.baseURL)/\(uri.trimming { $0 == "/" })"
                    )

                    let task = try await session.execute(
                        client: client,
                        request: request,
                        url: request.url.absoluteString,
                        readingMode: .length(1_024),
                        uploadingBytes: .zero,
                        cache: nil,
                        logger: nil
                    )

                    var count = 0

                    for try await _ in task.response {
                        count += 1
                    }

                    return count
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
