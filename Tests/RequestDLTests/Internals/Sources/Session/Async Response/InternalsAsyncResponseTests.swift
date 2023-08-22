/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsAsyncResponseTests: XCTestCase {

    func testResponse_whenOnlyUploading_shouldReceiveParts() async throws {
        // Given
        let uploadingBytes = 16
        let parts = 0 ..< uploadingBytes
        let configuration = response(uploadingBytes: uploadingBytes)

        // When
        for part in parts {
            configuration.upload.append(.success(part))
        }

        configuration.upload.close()
        configuration.head.close()
        configuration.download.close()

        let received = try await Array(configuration.response)

        // Then
        XCTAssertEqual(received, parts.map {
            .upload(.init(
                chunkSize: $0,
                totalSize: uploadingBytes
            ))
        })
    }

    func testResponse_whenOnlyHead_shouldReceiveHead() async throws {
        // Given
        let configuration = response()

        let head = Internals.ResponseHead(
            url: "https://127.0.0.1",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: .zero, major: 1),
            headers: .init(),
            isKeepAlive: false
        )

        // When
        configuration.head.append(.success(head))

        configuration.upload.close()
        configuration.head.close()
        configuration.download.close()

        let received = try await Array(configuration.response)

        // Then
        XCTAssertEqual(received, [.download(.init(
            head: head,
            bytes: .init(totalSize: .zero, stream: configuration.download)
        ))])
    }

    func testResponse_whenHeadWithBytes_shouldReceiveHeadAndBytes() async throws {
        // Given
        let configuration = response()

        let data = Data.randomData(length: 100_000_000)

        let head = Internals.ResponseHead(
            url: "https://127.0.0.1",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: .zero, major: 1),
            headers: .init([("Content-Length", String(data.count))]),
            isKeepAlive: false
        )

        // When
        configuration.head.append(.success(head))
        configuration.download.append(.success(.init(data)))

        configuration.upload.close()
        configuration.head.close()
        configuration.download.close()

        let received = try await Array(configuration.response)

        // Then
        XCTAssertEqual(received, [.download(.init(
            head: head,
            bytes: .init(totalSize: data.count, stream: configuration.download)
        ))])
    }
}

extension InternalsAsyncResponseTests {

    fileprivate struct Configuration {
        let uploadingBytes: Int
        let upload: Internals.AsyncStream<Int>
        let head: Internals.AsyncStream<Internals.ResponseHead>
        let download: Internals.AsyncStream<Internals.DataBuffer>
        let response: Internals.AsyncResponse
    }

    fileprivate func response(
        uploadingBytes: Int = .zero,
        upload: Internals.AsyncStream<Int> = .init(),
        head: Internals.AsyncStream<Internals.ResponseHead> = .init(),
        download: Internals.AsyncStream<Internals.DataBuffer> = .init()
    ) -> Configuration {
        let response = Internals.AsyncResponse(
            uploadingBytes: uploadingBytes,
            upload: upload,
            head: head,
            download: download
        )

        return .init(
            uploadingBytes: uploadingBytes,
            upload: upload,
            head: head,
            download: download,
            response: response
        )
    }
}
