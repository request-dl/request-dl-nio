/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class FormTests: XCTestCase {

    struct Mock: Codable {
        let foo: String
        let date: Date
    }

    // MARK: - Init with Data

    func testForm_whenInitDataWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"

        // When
        let parsed = try await parse {
            Form(name: name, data: data)
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    func testForm_whenInitDataFilenameWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"
        let filename = "raw_data"

        // When
        let parsed = try await parse {
            Form(name: name, filename: filename, data: data)
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    func testForm_whenInitDataFilenameContentTypeWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"
        let filename = "raw_data"
        let contentType = ContentType.pdf

        // When
        let parsed = try await parse {
            Form(
                name: name,
                filename: filename,
                contentType: contentType,
                data: data
            )
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            [String(contentType)]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    // MARK: - Init with URL

    func testForm_whenInitURLWithEmptyHeaders() async throws {
        // Given
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).form")
            .appendingPathExtension(".raw")

        var buffer = Internals.FileBuffer(url)
        let name = "message"

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        buffer.writeData(Data.randomData(length: 1_024))

        // When
        let parsed = try await parse {
            Form(name: name, contentType: .octetStream, url: url)
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, buffer.getData())
    }

    func testForm_whenInitURLFilenameWithEmptyHeaders() async throws {
        // Given
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).form")
            .appendingPathExtension(".raw")

        var buffer = Internals.FileBuffer(url)
        let name = "message"
        let filename = "raw_data"

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        buffer.writeData(Data.randomData(length: 1_024))

        // When
        let parsed = try await parse {
            Form(
                name: name,
                filename: filename,
                contentType: .octetStream,
                url: url
            )
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, buffer.getData())
    }

    func testForm_whenInitURLFilenameContentTypeWithEmptyHeaders() async throws {
        // Given
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).form")
            .appendingPathExtension(".raw")

        var buffer = Internals.FileBuffer(url)
        let name = "message"
        let filename = "raw_data"
        let contentType = ContentType.pdf

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        buffer.writeData(Data.randomData(length: 1_024))

        // When
        let parsed = try await parse {
            Form(
                name: name,
                filename: filename,
                contentType: contentType,
                url: url
            )
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            [String(contentType)]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, buffer.getData())
    }

    // MARK: - Init with String

    func testForm_whenInitStringWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"

        // When
        let parsed = try await parse {
            Form(name: name, data: data)
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    func testForm_whenInitStringFilenameWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"
        let filename = "raw_data"

        // When
        let parsed = try await parse {
            Form(name: name, filename: filename, data: data)
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    func testForm_whenInitStringFilenameContentTypeWithEmptyHeaders() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let name = "message"
        let filename = "raw_data"
        let contentType = ContentType.pdf

        // When
        let parsed = try await parse {
            Form(
                name: name,
                filename: filename,
                contentType: contentType,
                data: data
            )
        }

        // Then
        XCTAssertEqual(parsed.headers["Content-Type"], [
            "multipart/form-data; boundary=\"\(parsed.boundary)\""
        ])

        XCTAssertEqual(parsed.multipartForm.items.count, 1)

        guard parsed.multipartForm.items.count == 1 else {
            return
        }

        XCTAssertEqual(parsed.multipartForm.items[0].headers.count, 2)

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(name)\"; filename=\"\(filename)\""]
        )

        XCTAssertEqual(
            parsed.multipartForm.items[0].headers["Content-Type"],
            [String(contentType)]
        )

        XCTAssertEqual(parsed.multipartForm.items[0].contents, data)
    }

    func testForm_whenInitURLWithEmptyHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitStringWithEmptyHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitEncodableWithEmptyHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitJSONWithEmptyHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitDataWithCustomHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitURLWithCustomHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitStringWithCustomHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitEncodableWithCustomHeaders() {
        XCTFail("Hello world")
    }

    func testForm_whenInitJSONWithCustomHeaders() {
        XCTFail("Hello world")
    }

    func testNeverBody() async throws {
        // Given
        let property = FormData(Data(), forKey: "key", fileName: "123", type: .json)

        // Then
        try await assertNever(property.body)
    }

    func testData_whenPartLengthSet() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                Mock(foo: "bar", date: Date()),
                forKey: "data",
                fileName: "contents.json"
            )
            .payloadPartLength(length)
        })

        let sut = try await resolved.request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 1)
    }
}

extension FormTests {

    struct Parsed {
        let boundary: String
        let headers: HTTPHeaders
        let multipartForm: MultipartForm
    }

    func parse<Content: Property>(_ content: () -> Content) async throws -> Parsed {
        let resolved = try await resolve(TestProperty(content()))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try await MultipartFormParser(
            resolved.request.body?.buffers() ?? [],
            boundary: boundary
        ).parse()

        return .init(
            boundary: boundary,
            headers: resolved.request.headers,
            multipartForm: multipartForm
        )
    }
}
