//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
import struct Foundation.Data
#endif

/// Only the executor-agnostic half of this suite: every test here runs whichever executor
/// `resolveExecutor()` picks on its own, with nothing pinning it to `.nio`/`.nioTransportServices`
/// specifically. The half that does (mTLS, PSK, `.nioTransportServices`-specific trust-evaluator
/// regressions, `requiredExecutor(_:)` against `.nio`/`.nioTransportServices`) lives in
/// `DataTaskTests+NIO.swift`, which needs NIOCore to exist at all.
struct DataTaskTests {

    @Test
    func dataTask() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// A deadline this short is guaranteed to already have elapsed by the time the request even
    /// reaches the network: deterministic without needing an artificially slow server, the same
    /// technique real-network cancellation tests elsewhere in this suite rely on.
    @Test
    func dataTask_whenResourceTimeoutAlreadyElapsed_throwsResourceTimeoutError() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When / Then
        await #expect(throws: ResourceTimeoutError.self) {
            try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                Timeout(.nanoseconds(1), for: .resource)

                SecureConnection {
                    TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()
        }
    }

    @Test
    func dataTask_whenResourceTimeoutNotExceeded_completesNormally() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
            Timeout(.seconds(30), for: .resource)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// Stands in for any pre-flight step that can block for an unbounded stretch before the
    /// request itself starts: a descriptor hook doing its own I/O here, but equally a client
    /// cache entry whose lock is held by a slow neighbour, or a system-proxy PAC script being
    /// fetched and evaluated over the network.
    ///
    /// Reaching the deadline through a hook is what makes that class of stall testable at all —
    /// unlike the others, it is the one the caller supplies themselves.
    private struct StallingDescriptor: TaskDescriptor {

        func describe(_ context: TaskDescriptorContext) async throws -> Bool {
            try await _Concurrency.Task.sleep(nanoseconds: 30_000_000_000)
            return true
        }
    }

    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func dataTask_whenAPreFlightStepStallsPastTheResourceTimeout_throwsInsteadOfWaitingItOut()
        async throws
    {
        // Given: a `.resource` budget far shorter than a pre-flight step that runs before the
        // request is ever sent.
        let task = DataTask {
            BaseURL("example.com")
            Timeout(.milliseconds(200), for: .resource)
        }
        .description(StallingDescriptor()) { _ in }

        // When
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ResourceTimeoutError.self) {
            _ = try await task.result()
        }

        let elapsed = clock.now - start

        // Then: the budget bounds that step too, rather than starting to count only once it is
        // done. A wide margin below the 30s stall, since what a regression looks like here is
        // waiting the stall out in full, not missing the deadline by a hair -- and cancelling a
        // `Task.sleep` still has to wait for a free cooperative-pool thread, which a contended CI
        // simulator can stretch to several seconds on its own (see e.g. the O(n²) DiskStorage
        // fixes' own notes on simulator contention).
        #expect(elapsed < .seconds(15))
    }
}
