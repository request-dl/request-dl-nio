/*
 See LICENSE for this package's licensing information.
*/

import XCTest

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

        var fileBuffer = FileBuffer(url)
        fileBuffer.writeData(Data.randomData(length: length))

        // When
        try await InternalServer(
            host: "localhost",
            port: 8080,
            response: message
        ).run { baseURL in
            var request = Request(url: "https://\(baseURL)")
            request.method = "POST"
            request.body = RequestBody(fragment) {
                BodyItem(fileBuffer)
            }

            var secureConnection = Session.SecureConnection(.client)
            secureConnection.trustRoots = .certificates([
                .init(certificates.certificateURL.absolutePath(percentEncoded: false))
            ])
            session.configuration.secureConnection = secureConnection

            let task = try await session.request(request)

            var parts: [Int] = []
            var download: (ResponseHead, Data)?

            for try await result in task.response {
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
                try (download?.1).map(HTTPResult<String>.resolve),
                HTTPResult(
                    receivedBytes: length,
                    response: message
                )
            )
        }
    }
}
