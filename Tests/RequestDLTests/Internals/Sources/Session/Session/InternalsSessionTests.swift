/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsSessionTests: XCTestCase {

    var localServer: LocalServer!
    var session: Internals.Session!

    override func setUp() async throws {
        try await super.setUp()

        localServer = try await .init(.standard)
        localServer.cleanup()

        session = Internals.Session(
            provider: .shared,
            configuration: .init()
        )
    }

    override func tearDown() async throws {
        try await super.tearDown()

        localServer.cleanup()
        localServer = nil

        session = nil
    }

    func testSession_whenPerformingGet_shouldBeValid() async throws {
        // Given
        var request = Internals.Request()
        request.baseURL = "https://google.com"

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )

        let result = try await Array(task())

        // Then
        XCTAssertEqual(result.count, 1)

        guard case .download? = result.first else {
            XCTFail("The obtained result is different from the expected result")
            return
        }
    }

    func testSession_whenPerformingPostUploadingData_shouldBeValid() async throws {
        // Given
        let length = 1_023
        let data = Data.randomData(length: length)

        var request = Internals.Request()
        request.baseURL = "https://google.com"
        request.method = "POST"
        request.body = Internals.Body(buffers: [
            Internals.DataBuffer(data)
        ])

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )
        let result = try await Array(task())

        // Then
        XCTAssertEqual(result.count, length + 1)
        XCTAssertEqual(
            Array(result[0..<length]),
            (0..<length).map { _ in .upload(1) }
        )

        guard case .download? = result.last else {
            XCTFail("The obtained result is different from the expected result")
            return
        }
    }

    func testSession_whenPerformingPostEmptyData_shouldBeValid() async throws {
        // Given
        var request = Internals.Request()
        request.baseURL = "https://google.com"
        request.method = "POST"
        request.body = Internals.Body(buffers: [])

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )
        let result = try await Array(task())

        // Then
        XCTAssertEqual(result.count, 1)

        guard case .download? = result.first else {
            XCTFail("The obtained result is different from the expected result")
            return
        }
    }

    // swiftlint:disable function_body_length
    func testSession_whenUploadingFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().server()
        let message = "Hello World"

        let length = 100_000_000
        let fragment = 1_024 * 8

        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UploadingFile.txt")

        defer { try? url.removeIfNeeded() }
        try url.createPathIfNeeded()

        var fileBuffer = Internals.FileBuffer(url)
        fileBuffer.writeData(Data.randomData(length: length))

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

        // When
        var request = Internals.Request()
        request.baseURL = "https://\(localServer.baseURL)"
        request.method = "POST"
        request.body = Internals.Body(fragment, buffers: [
            fileBuffer
        ])

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .certificates([
            .init(certificates.certificateURL.absolutePath(percentEncoded: false), format: .pem)
        ])

        var configuration = session.configuration
        configuration.secureConnection = secureConnection

        let session = Internals.Session(
            provider: session.provider,
            configuration: configuration
        )

        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )

        var parts: [Int] = []
        var download: (ResponseHead, Data)?

        for try await result in task() {
            switch result {
            case .upload(let part):
                NSLog("Send %d bytes (%d)", part, parts.count)
                parts.append(part)
            case .download(let head, let bytes):
                NSLog("Head %d %@", head.status.code, head.status.reason)
                download = (head, try await Data(Array(bytes).joined()))
            }
        }

        // Then
        XCTAssertEqual(parts.count, Int(ceil(Double(length) / Double(fragment))))
        XCTAssertEqual(parts.reduce(.zero, +), fileBuffer.writerIndex)
        XCTAssertNotNil(download)
        XCTAssertEqual(download?.0.status.code, 200)
        XCTAssertEqual(
            try (download?.1).map(HTTPResult<String>.init),
            HTTPResult(
                receivedBytes: length,
                response: message
            )
        )
    }
    // swiftlint:enable function_body_length
}
