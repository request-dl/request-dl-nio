/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class DeprecatedModifiersProgressTests: XCTestCase {

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

    var localServer: LocalServer!
    var uploadMonitor: UploadProgressMonitor!
    var downloadMonitor: DownloadProgressMonitor!
    var progressMonitor: ProgressMonitor!

    override func setUp() async throws {
        try await super.setUp()

        localServer = try await .init(.standard)
        localServer.cleanup()

        uploadMonitor = .init()
        downloadMonitor = .init()
        progressMonitor = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        localServer.cleanup()
        localServer = nil

        uploadMonitor = nil
        downloadMonitor = nil
        progressMonitor = nil
    }

    func testDeprecatedProgress_whenUploadStep_shouldBeValid() async throws {
        // Given
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
        .uploadProgress(uploadMonitor)
        .extractPayload()
        .result()

        // Then
        XCTAssertEqual(uploadMonitor.sentBytes.reduce(.zero, +), data.count)
    }

    func testDeprecatedProgress_whenDownloadStep_shouldBeValid() async throws {
        // Given
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
        .downloadProgress(downloadMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(downloadMonitor.length, data.count)
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

    func testDeprecatedProgress_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
        // Given
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
        .downloadProgress(downloadMonitor, length: expectingData.count)
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(expectingData.count, data.count)
        XCTAssertEqual(downloadMonitor.length, data.count)
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
        }
        .progress(progressMonitor)
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(receivedData)

        // Then
        XCTAssertEqual(progressMonitor.length, receivedData.count)
        XCTAssertEqual(result.receivedBytes, data.count)

        let completeParts = progressMonitor.receivedData.dropLast()
        if !completeParts.isEmpty {
            XCTAssertEqual(
                completeParts.map(\.count),
                completeParts.indices.map { _ in length }
            )
        }

        XCTAssertLessThanOrEqual(progressMonitor.receivedData.last?.count ?? .zero, length)
    }
}
