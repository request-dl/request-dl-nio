//
// See LICENSE for this package's licensing information.
//

import Metrics
import MetricsTestKit
import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// What a session given a metrics factory reports of each request, and under which labels.
struct RequestMetricsReporterTests {

    // MARK: - Private types

    private struct Failure: Error {}

    /// A step ahead of the transport that outlasts any budget.
    private struct StallingDescriptor: TaskDescriptor {

        func describe(_ context: TaskDescriptorContext) async throws -> Bool {
            try await _Concurrency.Task.sleep(nanoseconds: 30_000_000_000)
            return true
        }
    }

    private typealias Executor = TransferTestExecutor

    private static let durationLabel = RequestMetricsReporter.durationLabel
    private static let requestBodySizeLabel = RequestMetricsReporter.requestBodySizeLabel
    private static let responseBodySizeLabel = RequestMetricsReporter.responseBodySizeLabel

    private func makeReporter(
        _ metrics: TestMetrics,
        url: String = "https://example.com/a?token=secret",
        method: String = "GET"
    ) -> RequestMetricsReporter {
        RequestMetricsReporter(factory: metrics, execution: RequestExecution(url: url, method: method))
    }

    private func transfer(total: Int) -> Internals.ExecutionObserver.Transfer {
        .init(bytes: total, total: total, expected: nil)
    }

    // MARK: - What is reported

    @Test
    func aResponse_reportsItsDurationAndTheBytesOfItsBody() throws {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics, method: "POST")

        // When
        reporter.receive(.state(.started))
        reporter.receive(.progress(upload: transfer(total: 300), download: nil))
        reporter.receive(.head(statusCode: 201))
        reporter.receive(.progress(upload: nil, download: transfer(total: 4_096)))
        reporter.receive(.state(.finished))

        // Then
        let dimensions = [
            ("http.request.method", "POST"),
            ("server.address", "example.com"),
            ("http.response.status_class", "2xx"),
        ]

        #expect(try metrics.expectTimer(Self.durationLabel, dimensions).values.count == 1)
        #expect(try metrics.expectRecorder(Self.requestBodySizeLabel, dimensions).values == [300])
        #expect(try metrics.expectRecorder(Self.responseBodySizeLabel, dimensions).values == [4_096])
    }

    /// The URL has a query and a path that can hold anything: neither is a label.
    @Test
    func theLabels_neverHoldAWholeURL() {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics, url: "https://example.com/users/42?token=secret")

        // When
        reporter.receive(.state(.started))
        reporter.receive(.head(statusCode: 200))
        reporter.receive(.state(.finished))

        // Then
        let values = metrics.timers.flatMap(\.dimensions).map(\.1)
        #expect(values.contains("example.com"))
        #expect(!values.contains { $0.contains("secret") || $0.contains("42") || $0.contains("/") })
    }

    @Test
    func aRequestWithoutABody_reportsNoRequestBodySize() {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics)

        // When
        reporter.receive(.state(.started))
        reporter.receive(.head(statusCode: 200))
        reporter.receive(.state(.finished))

        // Then
        #expect(metrics.recorders.map(\.label) == [Self.responseBodySizeLabel])
    }

    @Test(arguments: [(100, "1xx"), (204, "2xx"), (301, "3xx"), (404, "4xx"), (503, "5xx")])
    func theStatus_isReportedAsItsClass(_ status: Int, _ expected: String) throws {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics)

        // When
        reporter.receive(.state(.started))
        reporter.receive(.head(statusCode: status))
        reporter.receive(.state(.finished))

        // Then
        let timer = try #require(metrics.timers.first)
        #expect(timer.dimensions.contains { $0 == ("http.response.status_class", expected) })
    }

    @Test(arguments: [("get", "GET"), ("PATCH", "PATCH"), ("PROPFIND", "_OTHER"), ("", "_OTHER")])
    func theMethod_isOneHTTPDefinesOrOther(_ method: String, _ expected: String) throws {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics, method: method)

        // When
        reporter.receive(.state(.started))
        reporter.receive(.head(statusCode: 200))
        reporter.receive(.state(.finished))

        // Then
        let timer = try #require(metrics.timers.first)
        #expect(timer.dimensions.contains { $0 == ("http.request.method", expected) })
    }

    // MARK: - What is not

    @Test
    func aRequestThatFailed_reportsItsDurationWithTheTypeOfTheError() throws {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics)

        // When
        reporter.receive(.state(.started))
        reporter.receive(.state(.failed(Failure())))

        // Then
        let dimensions = [
            ("http.request.method", "GET"),
            ("server.address", "example.com"),
            ("error.type", "Failure"),
        ]

        #expect(try metrics.expectTimer(Self.durationLabel, dimensions).values.count == 1)
        #expect(metrics.recorders.isEmpty)
    }

    @Test
    func aTimeoutAndACancellation_areNamedNotTypedByTheirErrors() throws {
        // Given
        let timedOut = TestMetrics()
        let cancelled = TestMetrics()

        // When
        let first = makeReporter(timedOut)
        first.receive(.state(.started))
        first.receive(.state(.failed(ResourceTimeoutError())))

        let second = makeReporter(cancelled)
        second.receive(.state(.started))
        second.receive(.state(.failed(CancellationError())))

        // Then
        #expect(
            try timedOut.expectTimer(
                Self.durationLabel,
                [
                    ("http.request.method", "GET"),
                    ("server.address", "example.com"),
                    ("error.type", "timeout"),
                ]
            ).values.count == 1
        )

        #expect(
            try cancelled.expectTimer(
                Self.durationLabel,
                [
                    ("http.request.method", "GET"),
                    ("server.address", "example.com"),
                    ("error.type", "cancelled"),
                ]
            ).values.count == 1
        )
    }

    /// Nothing crossed the wire for it, so it is not a request, and what it took is not what a
    /// request takes.
    @Test
    func aResponseServedFromTheCache_reportsNothing() {
        // Given
        let metrics = TestMetrics()
        let reporter = makeReporter(metrics)

        // When: a response that ends without a head ever coming in.
        reporter.receive(.state(.started))
        reporter.receive(.state(.finished))

        // Then
        #expect(metrics.timers.isEmpty)
        #expect(metrics.recorders.isEmpty)
    }

    // MARK: - Through a session

    @Test(arguments: Executor.allCases)
    private func aSessionWithAFactory_reportsTheRequestsItMakes(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 4_096)) { server in
            // Given
            let metrics = TestMetrics()

            // When
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.pinnedSession.metricsFactory(metrics)
            }
            .result()

            // Then: delivered from a task of its own, once the request is over.
            let dimensions = [
                ("http.request.method", "GET"),
                ("server.address", "127.0.0.1"),
                ("http.response.status_class", "2xx"),
            ]

            try await eventually(timeout: 30) { !metrics.timers.isEmpty }

            #expect(try metrics.expectTimer(Self.durationLabel, dimensions).values.count == 1)
            #expect(try metrics.expectRecorder(Self.responseBodySizeLabel, dimensions).values == [4_096])
        }
    }

    @Test(arguments: Executor.allCases)
    private func aSessionWithoutAFactory_reportsNothing(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: a factory that the session was never given.
            let metrics = TestMetrics()

            // When
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .result()

            try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

            // Then
            #expect(metrics.timers.isEmpty)
            #expect(metrics.recorders.isEmpty)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aRequestThatEndsBeforeTheTransport_isReportedWithItsError(_ executor: Executor) async throws {
        // Given
        let metrics = TestMetrics()

        // When: the resource budget runs out in a step ahead of the transport.
        await #expect(throws: ResourceTimeoutError.self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:1")
                Path("/resource")
                executor.pinnedSession.metricsFactory(metrics)
                Timeout(.milliseconds(200), for: .resource)
            }
            .description(StallingDescriptor()) { _ in }
            .result()
        }

        // Then
        try await eventually(timeout: 30) { !metrics.timers.isEmpty }

        let dimensions = [
            ("http.request.method", "GET"),
            ("server.address", "127.0.0.1"),
            ("error.type", "timeout"),
        ]

        #expect(try metrics.expectTimer(Self.durationLabel, dimensions).values.count == 1)
    }
}
