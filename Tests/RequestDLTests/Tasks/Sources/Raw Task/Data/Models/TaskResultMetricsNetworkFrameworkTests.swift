//
// See LICENSE for this package's licensing information.
//

// The `.nioTransportServices` half of `TaskResultMetricsTests`: AsyncHTTPClient derives the connection
// phases from `NWConnection.EstablishmentReport` there, and the Network framework is the only transport
// that knows the negotiated TLS cipher suite and reports the DNS lookup without
// `Session.collectDNSMetrics(_:)`.
#if canImport(NIOCore) && canImport(Network)

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct TaskResultMetricsNetworkFrameworkTests {

    @Test
    func dataTask_reportsTheTLSAndTheCipherSuiteOnlyThisTransportKnows() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await request(localServer, uri: uri, session: session()).result()

        // Then
        let metrics = try #require(result.metrics)
        #expect(metrics.transactions.count == 1)

        let connection = try #require(metrics.transactions.first?.connection)
        #expect(connection.isReused == false)
        #expect(connection.negotiatedProtocol == .http1_1)
        #expect(connection.tlsVersion != nil)
        #expect(connection.tlsCipherSuite != nil)
        #expect(connection.remotePort == Int(localServer.baseURL.split(separator: ":").last ?? ""))
        #expect(connection.isProxyConnection == false)
    }

    @Test
    func dataTask_reportsEveryConnectionPhaseInOrder() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await request(localServer, uri: uri, session: session()).result()

        // Then: the report only has whole milliseconds, so the phases are laid out one after the other.
        let connection = try #require(result.metrics?.transactions.first?.connection)
        let lookup = try #require(connection.domainLookup)
        let connect = try #require(connection.connect)
        let secure = try #require(connection.secureConnection)

        #expect(lookup.start <= lookup.end)
        #expect(lookup.end <= connect.start)
        #expect(connect.start <= connect.end)
        #expect(connect.end <= secure.start)
        #expect(secure.start <= secure.end)
    }

    @Test
    func dataTask_reportsTheDNSLookupWithoutAskingForIt() async throws {
        // Given: `collectDNSMetrics` is off, which only matters to the POSIX transport.
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        // When
        let result = try await request(localServer, uri: uri, session: session()).result()

        // Then
        #expect(result.metrics?.transactions.first?.connection?.domainLookup != nil)
    }

    @Test
    func dataTask_whenSecondRequestSharesTheSession_reportsTheConnectionAsReused() async throws {
        // Given
        let (localServer, uri) = try await makeServer()
        defer { localServer.cleanup(at: uri) }

        let session = session()
        _ = try await request(localServer, uri: uri, session: session).result()

        // When
        let second = try await request(localServer, uri: uri, session: session).result()

        // Then: it did not go through the phases that establish a connection.
        let connection = try #require(second.metrics?.transactions.first?.connection)
        #expect(connection.isReused == true)
        #expect(connection.domainLookup == nil)
        #expect(connection.connect == nil)
        #expect(connection.secureConnection == nil)
    }

    // MARK: - Private methods

    private func session() -> String {
        "com.requestdl.tests.metrics.nwframework.\(UUID())"
    }

    private func makeServer() async throws -> (LocalServer, String) {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello World"), at: uri)

        return (localServer, uri)
    }

    private func request(_ localServer: LocalServer, uri: String, session: String) -> some RequestTask<TaskResult<Data>>
    {
        DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session(session)
                .requiredExecutor(.nioTransportServices)

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
    }
}

#endif
