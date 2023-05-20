/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersProgressTests: XCTestCase {

    class UploadProgressMonitor: UploadProgress {
        var sentBytes: [Int] = []

        func upload(_ bytesLength: Int) {
            sentBytes.append(bytesLength)
        }
    }

    class DownloadProgressMonitor: DownloadProgress {

        var receivedData: [Data] = []
        var length: Int?

        func download(_ part: Data, length: Int?) {
            receivedData.append(part)
            self.length = length
        }
    }

    class ProgressMonitor: RequestDL.Progress {

        var sentBytes: [Int] = []

        var receivedData: [Data] = []
        var length: Int?

        func upload(_ bytesLength: Int) {
            sentBytes.append(bytesLength)
        }

        func download(_ part: Data, length: Int?) {
            receivedData.append(part)
            self.length = length
        }
    }

    var uploadMonitor: UploadProgressMonitor!
    var downloadMonitor: DownloadProgressMonitor!
    var progressMonitor: ProgressMonitor!

    override func setUp() async throws {
        try await super.setUp()
        uploadMonitor = .init()
        downloadMonitor = .init()
        progressMonitor = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        uploadMonitor = nil
        downloadMonitor = nil
        progressMonitor = nil
    }

    func testIgnores_whenUploadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let data = Data.randomData(length: 1_024 * 64)

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: ""
        ).run { baseURL in
            _ = try await UploadTask {
                BaseURL(baseURL)
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
    }

    func testIgnores_whenDownloadStep_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let data = try await UploadTask {
                BaseURL(baseURL)
                Path("index")

                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                    }
                }

                ReadingMode(length: length)
            }
            .ignoresUploadProgress()
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
    }

    func testIgnores_whenDownloadStepAfterExtractingPayload_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        let expectingData = try HTTPResult(
            receivedBytes: .zero,
            response: message
        ).encode()

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let data = try await UploadTask {
                BaseURL(baseURL)
                Path("index")

                SecureConnection {
                    Trusts {
                        RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                    }
                }

                ReadingMode(length: length)
            }
            .ignoresUploadProgress()
            .extractPayload()
            .downloadProgress(downloadMonitor, length: expectingData.count)
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
    }

    func testIgnores_whenCompleteProgress_shouldBeValid() async throws {
        // Given
        let resource = Certificates().server()
        let data = Data.randomData(length: 1_024 * 64)
        let message = String(repeating: "c", count: 1_024 * 64)
        let length = 1_024

        // When
        try await InternalServer(
            host: "localhost",
            port: 8888,
            response: message
        ).run { baseURL in
            let receivedData = try await UploadTask {
                BaseURL(baseURL)
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
}
