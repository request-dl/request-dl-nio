/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsAsyncResponseTests: XCTestCase {

    var upload: Internals.DataStream<Int>!
    var head: Internals.DataStream<Internals.ResponseHead>!
    var download: Internals.DataStream<Internals.DataBuffer>!
    var response: Internals.AsyncResponse!

    override func setUp() async throws {
        try await super.setUp()

        upload = .init()
        head = .init()
        download = .init()

        response = .init(
            upload: upload,
            head: head,
            download: download
        )
    }

    override func tearDown() async throws {
        try await super.tearDown()

        upload = nil
        head = nil
        download = nil
        response = nil
    }

    func testResponse_whenOnlyUploading_shouldReceiveParts() async throws {
        // Given
        let parts = 0 ..< 16

        // When
        for part in parts {
            upload.append(.success(part))
        }

        upload.close()
        head.close()
        download.close()

        let received = try await Array(response)

        // Then
        XCTAssertEqual(received, parts.map { .upload($0) })
    }

    func testResponse_whenOnlyHead_shouldReceiveHead() async throws {
        // Given
        let head = Internals.ResponseHead(
            url: "https://localhost",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: .zero, major: 1),
            headers: .init(),
            isKeepAlive: false
        )

        // When
        self.head.append(.success(head))

        upload.close()
        self.head.close()
        download.close()

        let received = try await Array(response)

        // Then
        XCTAssertEqual(received, [.download(head, .init(download))])
    }

    func testResponse_whenHeadWithBytes_shouldReceiveHeadAndBytes() async throws {
        // Given
        let head = Internals.ResponseHead(
            url: "https://localhost",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: .zero, major: 1),
            headers: .init(),
            isKeepAlive: false
        )

        let data = Data.randomData(length: 100_000_000)

        // When
        self.head.append(.success(head))
        self.download.append(.success(.init(data)))

        upload.close()
        self.head.close()
        download.close()

        let received = try await Array(response)

        // Then
        XCTAssertEqual(received, [.download(head, .init(download))])
    }
}
