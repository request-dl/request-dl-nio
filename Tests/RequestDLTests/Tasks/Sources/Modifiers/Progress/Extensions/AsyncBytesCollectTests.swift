//
// See LICENSE for this package's licensing information.
//

import Logging
import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import struct Foundation.UUID
#endif

struct AsyncBytesCollectTests {

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
    func collect_whenLoggerEnabledAtTraceLevel_shouldLogReceivedBytesAndFetchedDataMetadata() async throws {
        // Given
        let testState = try await TestState()
        let localServer = testState.localServer
        let resource = Certificates().server()
        let data = await Data.randomData(length: 1_024 * 8)
        let length = 256

        localServer.insert(.init(data: data), at: testState.uri)

        let recordBox = RecordBox()

        // When
        _ = try await Logger.withTesting(
            level: .trace,
            recorded: { recordBox.append($0) },
            perform: {
                try await UploadTask {
                    BaseURL(localServer.baseURL)
                    Path(testState.uri)

                    Session.localServer

                    SecureConnection {
                        TrustRoots {
                            RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                        }
                    }

                    ReadingMode(length: length)
                }
                .collectData()
                .extractPayload()
                .result()
            }
        )

        // Then
        let receivedBytesRecords = recordBox.records.filter {
            $0.metadata["raw_bytes"] != nil && $0.metadata["total_size"] != nil
        }
        let fetchedDataRecords = recordBox.records.filter {
            $0.metadata["raw_bytes"] != nil && $0.metadata["total_size"] == nil
        }

        #expect(!receivedBytesRecords.isEmpty)
        #expect(!fetchedDataRecords.isEmpty)
    }
}
