/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import _RequestDLExtensions
@testable import RequestDLInternals

class SessionTests: XCTestCase {

    var session: Session!

    override func setUp() async throws {
        try await super.setUp()

        session = try await Session(
            provider: .shared,
            configuration: .init()
        )
    }

    override func tearDown() async throws {
        try await super.tearDown()
        session = nil
    }

    func testSession_whenPerformingGet_shouldBeValid() async throws {
        // Given
        let request = Request(url: "https://google.com")

        // When
        let task = try await session.request(request)
        let result = try await Array(task.response)

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

        var request = Request(url: "https://google.com")
        request.method = "POST"
        request.body = RequestBody {
            BodyItem(data)
        }

        // When
        let task = try await session.request(request)
        let result = try await Array(task.response)

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
        var request = Request(url: "https://google.com")
        request.method = "POST"
        request.body = RequestBody {}

        // When
        let task = try await session.request(request)
        let result = try await Array(task.response)

        // Then
        XCTAssertEqual(result.count, 1)

        guard case .download? = result.first else {
            XCTFail("The obtained result is different from the expected result")
            return
        }
    }

    #if os(macOS) || os(Linux)
    func testSession_whenUploadingFile_shouldBeValid() async throws {
        // Given
        let server = try OpenSSL().certificate()
        let output = "Hello World"

        let length = 1_024
        let fragment = 64
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UploadingFile.txt")

        defer { try? FileManager.default.removeItem(at: url) }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        var fileBuffer = FileBuffer(url)
        fileBuffer.writeData(Data.randomData(length: length))

        var request = Request(url: "https://localhost:8080/index")
        request.method = "GET"
        request.body = RequestBody(fragment) {
            BodyItem(fileBuffer)
        }

        var secureConnection = Session.SecureConnection(.client)
        secureConnection.trustRoots = .file(server.certificateURL.path)
        session.configuration.secureConnection = secureConnection

        // When
        let openSSLServer = OpenSSLServer(output, certificate: server)
        try await openSSLServer.start {
            let task = try await session.request(request)
            
            var parts: [Int] = []
            var download: (ResponseHead, AsyncBytes)?
            
            for try await result in task.response {
                switch result {
                case .upload(let part):
                    NSLog("Send %d bytes (%d)", part, parts.count)
                    parts.append(part)
                case .download(let head, let bytes):
                    NSLog("Head %d %@", head.status.code, head.status.reason)
                    download = (head, bytes)
                }
            }
            
            // Then
            XCTAssertEqual(parts.count, Int(ceil(Double(length) / Double(fragment))))
            XCTAssertEqual(parts.reduce(.zero, +), fileBuffer.writerIndex)
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.0.status.code, 200)
        }
    }
    #endif
}
