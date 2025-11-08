/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

@available(*, deprecated)
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

    var localServer: LocalServer?
    var uploadMonitor: UploadProgressMonitor?
    var downloadMonitor: DownloadProgressMonitor?
    var progressMonitor: ProgressMonitor?

    override func setUp() async throws {
        try await super.setUp()

        localServer = try await .init(.standard)
        localServer?.cleanup()

        uploadMonitor = .init()
        downloadMonitor = .init()
        progressMonitor = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        localServer?.cleanup()
        localServer = nil

        uploadMonitor = nil
        downloadMonitor = nil
        progressMonitor = nil
    }

    @Test
    func deprecatedProgress_whenUploadStep_shouldBeValid() async throws {
        // Given
        let localServer = try #require(localServer)
        let uploadMonitor = try #require(uploadMonitor)

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
                    Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
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
        // Given
        let localServer = try #require(localServer)
        let downloadMonitor = try #require(downloadMonitor)

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
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        #expect(downloadMonitor.receivedData.last?.count ?? .zero <= length)
    }

    @Test
    func deprecatedProgress_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
        // Given
        let localServer = try #require(localServer)
        let downloadMonitor = try #require(downloadMonitor)

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
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        #expect(downloadMonitor.receivedData.last?.count ?? .zero <= length)
    }

    @Test
    func progress_whenCompleteProgress_shouldBeValid() async throws {
        // Given
        let localServer = try #require(localServer)
        let progressMonitor = try #require(progressMonitor)

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
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        #expect(progressMonitor.receivedData.last?.count ?? .zero <= length)
    }
}
