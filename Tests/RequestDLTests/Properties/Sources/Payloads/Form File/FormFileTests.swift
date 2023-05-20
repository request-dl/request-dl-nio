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

/*
    func testFileFormWithFileNameAndContentType() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "file.pdf",
            type: .pdf
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try await MultipartFormParser(
            resolved.request.body?.buffers() ?? [],
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(property.key)\"; filename=\"\(property.fileName)\""]
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            [String(property.contentType)]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testEmptyFileName() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "",
            type: .pdf
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try await MultipartFormParser(
            resolved.request.body?.buffers() ?? [],
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(property.key)\"; filename=\"\""]
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            [String(property.contentType)]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testFileNameResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let fileName = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: .pdf
        ).fileName

        // Then
        XCTAssertEqual(fileName, "bar.pdf")
    }

    func testContentTypeResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, .pdf)
    }

    func testOctetStreamResolved() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, "application/octet-stream")
    }

    func testNeverBody() async throws {
        // Given
        let property = FormFile(
            FileManager.default.temporaryDirectory,
            forKey: "key",
            fileName: nil,
            type: nil
        )

        // Then
        try await assertNever(property.body)
    }

    func testFile_whenPartLengthSet() async throws {
        // Given
        let length = 1_024
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")

        try Data(value.utf8).write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: "document",
                fileName: nil,
                type: nil
            )
            .payloadPartLength(length)
        })

        let sut = try await resolved.request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 1)
    }
}
*/
