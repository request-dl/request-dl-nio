/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct DeprecatedModifiersProgressTests {

    final class UploadProgressMonitor: UploadProgress, @unchecked Sendable {

        var sentBytes: [Int] {
            lock.withLock { _sentBytes }
        }

        private let lock = Lock()
        private var _sentBytes: [Int] = []

        func upload(_ chunkSize: Int, totalSize: Int) {
            lock.withLock {
                _sentBytes.append(chunkSize)
            }
        }
    }

    final class DownloadProgressMonitor: DownloadProgress, @unchecked Sendable {

        var length: Int? {
            lock.withLock { _length }
        }

        var receivedData: [Data] {
            lock.withLock { _receivedData }
        }

        private let lock = Lock()
        private var _receivedData: [Data] = []
        private var _length: Int?

        func download(_ slice: Data, totalSize: Int) {
            lock.withLock {
                _receivedData.append(slice)
                _length = totalSize
            }
        }
    }

    class ProgressMonitor: RequestDL.Progress, @unchecked Sendable {

        var sentBytes: [Int] {
            lock.withLock { _sentBytes }
        }

        var length: Int? {
            lock.withLock { _length }
        }

        var receivedData: [Data] {
            lock.withLock { _receivedData }
        }

        private let lock = Lock()
        private var _sentBytes: [Int] = []

        private var _receivedData: [Data] = []
        private var _length: Int?

        func upload(_ chunkSize: Int, totalSize: Int) {
            lock.withLock {
                _sentBytes.append(chunkSize)
            }
        }

        func download(_ slice: Data, totalSize: Int) {
            lock.withLock {
                _receivedData.append(slice)
                _length = totalSize
            }
        }
    }

    final class TestState: Sendable {

        let uri: String
        let localServer: LocalServer
        let uploadMonitor: UploadProgressMonitor
        let downloadMonitor: DownloadProgressMonitor
        let progressMonitor: ProgressMonitor

        init() async throws {
            uri = "/" + UUID().uuidString
            localServer = try await .init(.standard)
            localServer.cleanup(at: uri)

            uploadMonitor = .init()
            downloadMonitor = .init()
            progressMonitor = .init()
        }

        deinit {
            localServer.cleanup(at: uri)
        }
    }

    @Test
    func deprecatedProgress_whenUploadStep_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let uploadMonitor = testState.uploadMonitor

        let resource = Certificates().server()
        let data = Data.randomData(length: 1_024 * 64)

        let response = LocalServer.ResponseConfiguration(
            data: data
        )

        localServer.insert(response, at: testState.uri)

        // When
        _ = try await UploadTask {
            Session()
                .disableNetworkFramework()

            BaseURL(localServer.baseURL)
            Path(testState.uri)
            Payload(data: data)

            SecureConnection {
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }
        }
        .uploadProgress(uploadMonitor)
        .extractPayload()
        .result()

        // Then
        #expect(uploadMonitor.sentBytes.reduce(.zero, +) == data.count)
    }

    @Test
    func deprecatedProgress_whenDownloadStep_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let downloadMonitor = testState.downloadMonitor

        let resource = Certificates().server()
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: testState.uri)

        // When
        let data = try await UploadTask {
            Session()
                .disableNetworkFramework()

            BaseURL(localServer.baseURL)
            Path(testState.uri)

            SecureConnection {
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .downloadProgress(downloadMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(downloadMonitor.length == data.count)
        #expect(result.receivedBytes == .zero)

        let completeParts = downloadMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            #expect(
                completeParts.map(\.count) == completeParts.indices.map { _ in length }
            )
        }

        #expect(downloadMonitor.receivedData.last?.count ?? .zero <= length)
    }

    @Test
    func deprecatedProgress_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let downloadMonitor = testState.downloadMonitor

        let resource = Certificates().server()
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: testState.uri)

        let expectingData = try HTTPResult(
            receivedBytes: .zero,
            response: message
        ).encode()

        // When
        let data = try await UploadTask {
            Session()
                .disableNetworkFramework()

            BaseURL(localServer.baseURL)
            Path(testState.uri)

            SecureConnection {
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .extractPayload()
        .downloadProgress(downloadMonitor, length: expectingData.count)
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(expectingData.count == data.count)
        #expect(downloadMonitor.length == data.count)
        #expect(result.receivedBytes == .zero)

        let completeParts = downloadMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            #expect(
                completeParts.map(\.count) == completeParts.indices.map { _ in length }
            )
        }

        #expect(downloadMonitor.receivedData.last?.count ?? .zero <= length)
    }

    @Test
    func progress_whenCompleteProgress_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let progressMonitor = testState.progressMonitor

        let resource = Certificates().server()
        let data = Data.randomData(length: 1_024 * 64)
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: testState.uri)

        // When
        let receivedData = try await UploadTask {
            Session()
                .disableNetworkFramework()

            BaseURL(localServer.baseURL)
            Path(testState.uri)

            ReadingMode(length: length)

            SecureConnection {
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            Payload(data: data)
        }
        .progress(progressMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(receivedData)

        // Then
        #expect(progressMonitor.length == receivedData.count)
        #expect(result.receivedBytes == data.count)

        let completeParts = progressMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            #expect(
                completeParts.map(\.count) == completeParts.indices.map { _ in length }
            )
        }

        #expect(progressMonitor.receivedData.last?.count ?? .zero <= length)
    }
}
