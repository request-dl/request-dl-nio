//
// See LICENSE for this package's licensing information.
//

import Logging
import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

struct AsyncResponseCollectTests {

    final class UploadProgressMonitor: UploadProgress, @unchecked Sendable {
        func upload(_ chunkSize: Int, totalSize: Int) {}
    }

    final class RecordBox: @unchecked Sendable {

        var records: [TestLogHandler.LogRecord] {
            lock.withLock { _records }
        }

        private let lock = Lock()
        private var _records: [TestLogHandler.LogRecord] = []

        func append(_ record: TestLogHandler.LogRecord) {
            lock.withLock { _records.append(record) }
        }
    }

    final class TestState: Sendable {

        let uri: String
        let localServer: LocalServer

        init() async throws {
            uri = "/" + UUID().uuidString
            localServer = try await .init(.standard)
            localServer.cleanup(at: uri)
        }

        deinit {
            localServer.cleanup(at: uri)
        }
    }

    @Test
    func collect_whenLoggerEnabledAtTraceLevel_shouldLogUploadStepAndResponseHeadMetadata() async throws {
        // Given
        let testState = try await TestState()
        let localServer = testState.localServer
        let resource = Certificates().server()
        let data = await Data.randomData(length: 1_024)

        localServer.insert(.init(data: Data()), at: testState.uri)

        let recordBox = RecordBox()

        // When
        _ = try await Logger.withTesting(
            level: .trace,
            recorded: { recordBox.append($0) },
            perform: {
                try await UploadTask {
                    BaseURL(localServer.baseURL)
                    Path(testState.uri)
                    Payload(data: data)

                    Session.localServer

                    SecureConnection {
                        TrustRoots {
                            RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                        }
                    }
                }
                .collectData()
                .extractPayload()
                .result()
            }
        )

        // Then
        let uploadStepRecords = recordBox.records.filter {
            $0.metadata["chunk_size"] != nil && $0.metadata["total_size"] != nil
        }
        let responseHeadRecords = recordBox.records.filter {
            $0.metadata["status"] != nil && $0.metadata["version"] != nil && $0.metadata["keep_alive"] != nil
        }

        #expect(!uploadStepRecords.isEmpty)
        #expect(!responseHeadRecords.isEmpty)
    }

    @Test
    func collect_whenSequenceEndsWithoutDownloadStep_shouldThrowRequestFailureError() async throws {
        // Given
        let response = Internals.AsyncResponse(
            logger: nil,
            uploadingBytes: .zero,
            upload: .empty(),
            head: .empty(),
            download: .empty()
        )
        let asyncResponse = AsyncResponse(seed: .withoutCancellation, response: response)

        // When / Then
        await #expect(throws: RequestFailureError.self) {
            _ = try await asyncResponse.collect()
        }
    }

    @Test
    func collectWithProgress_whenSequenceEndsWithoutDownloadStep_shouldThrowRequestFailureError() async throws {
        // Given
        let response = Internals.AsyncResponse(
            logger: nil,
            uploadingBytes: .zero,
            upload: .empty(),
            head: .empty(),
            download: .empty()
        )
        let asyncResponse = AsyncResponse(seed: .withoutCancellation, response: response)
        let progress = UploadProgressMonitor()

        // When / Then
        await #expect(throws: RequestFailureError.self) {
            _ = try await asyncResponse.collect(with: progress)
        }
    }
}
