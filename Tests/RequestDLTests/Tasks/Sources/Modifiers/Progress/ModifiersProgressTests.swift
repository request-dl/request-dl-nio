/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersProgressTests: XCTestCase {

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

    func testProgress_whenUploadStep_shouldBeValid() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
        let uploadMonitor = try XCTUnwrap(uploadMonitor)

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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }
        }
        .progress(upload: uploadMonitor)
        .extractPayload()
        .result()

        // Then
        XCTAssertEqual(uploadMonitor.uploadedBytes.reduce(.zero, +), data.count)
    }

    func testProgress_whenDownloadStep_shouldBeValid() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
        let downloadMonitor = try XCTUnwrap(downloadMonitor)

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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .progress(download: downloadMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(downloadMonitor.totalSize, data.count)
        XCTAssertEqual(result.receivedBytes, .zero)

        let completeParts = downloadMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            XCTAssertEqual(
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        XCTAssertLessThanOrEqual(downloadMonitor.receivedData.last?.count ?? .zero, length)
    }

    func testProgress_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
        let downloadMonitor = try XCTUnwrap(downloadMonitor)

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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            ReadingMode(length: length)
        }
        .collectBytes()
        .extractPayload()
        .progress(download: downloadMonitor)
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(expectingData.count, data.count)
        XCTAssertEqual(downloadMonitor.totalSize, data.count)
        XCTAssertEqual(result.receivedBytes, .zero)

        let completeParts = downloadMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            XCTAssertEqual(
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        XCTAssertLessThanOrEqual(downloadMonitor.receivedData.last?.count ?? .zero, length)
    }

    func testProgress_whenCompleteProgress_shouldBeValid() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
        let progressMonitor = try XCTUnwrap(progressMonitor)

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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            Payload(data: data)
                .payloadChunkSize(64)
        }
        .progress(progressMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(receivedData)

        // Then
        XCTAssertEqual(result.receivedBytes, data.count)

        XCTAssertEqual(progressMonitor.upload.totalSize, data.count)
        XCTAssertEqual(progressMonitor.download.totalSize, receivedData.count)

        XCTAssertEqual(
            progressMonitor.upload.uploadedBytes,
            stride(from: .zero, to: data.count, by: 64).map { _ in 64 }
        )

        let completeParts = progressMonitor.download.receivedData.dropLast()
        if !completeParts.isEmpty {
            XCTAssertEqual(
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        XCTAssertLessThanOrEqual(progressMonitor.download.receivedData.last?.count ?? .zero, length)
    }
}
