/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersProgressTests {

    final class UploadProgressMonitor: UploadProgress, @unchecked Sendable {

        var uploadedBytes: [Int] {
            lock.withLock { _uploadedBytes }
        }

        var totalSize: Int {
            lock.withLock { _totalSize }
        }

        private let lock = Lock()

        private var _uploadedBytes: [Int] = []
        private var _totalSize: Int = .zero

        func upload(_ chunkSize: Int, totalSize: Int) {
            lock.withLock {
                _uploadedBytes.append(chunkSize)
                _totalSize = totalSize
            }
        }
    }

    final class DownloadProgressMonitor: DownloadProgress, @unchecked Sendable {

        var receivedData: [Data] {
            lock.withLock { _receivedData }
        }

        var totalSize: Int {
            lock.withLock { _totalSize }
        }

        private let lock = Lock()

        private var _receivedData: [Data] = []
        private var _totalSize: Int = .zero

        func download(_ slice: Data, totalSize: Int) {
            lock.withLock {
                _receivedData.append(slice)
                _totalSize = totalSize
            }
        }
    }

    final class ProgressMonitor: RequestDL.Progress, Sendable {

        let upload = UploadProgressMonitor()
        let download = DownloadProgressMonitor()

        func upload(_ chunkSize: Int, totalSize: Int) {
            upload.upload(chunkSize, totalSize: totalSize)
        }

        func download(_ slice: Data, totalSize: Int) {
            download.download(slice, totalSize: totalSize)
        }
    }

    final class TestState: Sendable {

        let localServer: LocalServer
        let uploadMonitor: UploadProgressMonitor
        let downloadMonitor: DownloadProgressMonitor
        let progressMonitor: ProgressMonitor

        init() async throws {
            localServer = try await .init(.standard)
            localServer.cleanup()

            uploadMonitor = .init()
            downloadMonitor = .init()
            progressMonitor = .init()
        }

        deinit {
            localServer.cleanup()
        }
    }

    @Test
    func progress_whenUploadStep_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let uploadMonitor = testState.uploadMonitor

        let resource = Certificates().server()
        let data = Data.randomData(length: 1_024 * 64)

        let response = LocalServer.ResponseConfiguration(
            data: data
        )

        localServer.insert(response)

        // When
        _ = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")
            Payload(data: data)

            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }
        }
        .progress(upload: uploadMonitor)
        .extractPayload()
        .result()

        // Then
        #expect(uploadMonitor.uploadedBytes.reduce(.zero, +) == data.count)
    }

    @Test
    func progress_whenDownloadStep_shouldBeValid() async throws {
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

        localServer.insert(response)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .progress(download: downloadMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(downloadMonitor.totalSize == data.count)
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
    func progress_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
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

        localServer.insert(response)

        let expectingData = try HTTPResult(
            receivedBytes: .zero,
            response: message
        ).encode()

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .extractPayload()
        .progress(download: downloadMonitor)
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(expectingData.count == data.count)
        #expect(downloadMonitor.totalSize == data.count)
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

        localServer.insert(response)

        // When
        let receivedData = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")

            ReadingMode(length: length)

            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }

            Payload(data: data)
                .payloadChunkSize(64)
        }
        .progress(progressMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(receivedData)

        // Then
        #expect(result.receivedBytes == data.count)

        #expect(progressMonitor.upload.totalSize == data.count)
        #expect(progressMonitor.download.totalSize == receivedData.count)

        #expect(
            progressMonitor.upload.uploadedBytes == stride(
                from: .zero,
                to: data.count,
                by: 64
            ).map { _ in 64 }
        )

        let completeParts = progressMonitor.download.receivedData.dropLast()
        if !completeParts.isEmpty {
            #expect(
                completeParts.map(\.count) == completeParts.indices.map { _ in length }
            )
        }

        #expect(progressMonitor.download.receivedData.last?.count ?? .zero <= length)
    }
}
