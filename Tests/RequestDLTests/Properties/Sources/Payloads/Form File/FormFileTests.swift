/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class FormFileTests: XCTestCase {

    var url: URL!

    override func setUp() async throws {
        try await super.setUp()

        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form.file.\(UUID())")
            .appendingPathExtension("raw")

        try url.createPathIfNeeded()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try url.removeIfNeeded()
    }

    func testForm_whenInitWithNilFilenameContentType() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: name,
                fileName: nil,
                type: nil
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items, [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(url.lastPathComponent)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenInitWithNilContentType() async throws {
        // Given
        let name = "foo"
        let filename = "bar"
        let data = Data.randomData(length: 1_024)

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: name,
                fileName: filename,
                type: nil
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items, [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenInitWithContentType() async throws {
        // Given
        let name = "foo"
        let filename = "bar"
        let data = Data.randomData(length: 1_024)
        let contentType = ContentType.pdf

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: name,
                fileName: filename,
                type: contentType
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items, [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                    ("Content-Type", String(contentType)),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenInitWithNilFilenameContentTypeAndPartLength() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)
        let partLength = 4

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: name,
                fileName: nil,
                type: nil
            )
            .payloadPartLength(partLength)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let buffers = try await resolved.request.body?.buffers() ?? []
        let spiltData = buffers.compactMap { $0.getData() }.reduce(Data(), +)
        let totalBytes = spiltData.count

        // Then
        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: totalBytes, by: partLength).map {
                let upperBound = $0 + partLength
                return spiltData[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items, [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(url.lastPathComponent)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = FormFile(
            url,
            forKey: "key",
            fileName: "name",
            type: nil
        )

        // Then
        try await assertNever(property.body)
    }
}
