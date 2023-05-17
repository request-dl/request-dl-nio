/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class FormValueTests: XCTestCase {

    func testValue_whenInitWithStringValue() async throws {
        // Given
        let key = "title"
        let value = "value"

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(key: key, value: value)
        })

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
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testValue_whenInitWithLosslessValue() async throws {
        // Given
        let key = "title"
        let value = 123

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(key: key, value: value)
        })

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
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data("\(value)".utf8))
    }

    func testNeverBody() async throws {
        // Given
        let property = FormValue.init(key: "key", value: "123")

        // Then
        try await assertNever(property.body)
    }
}

@available(*, deprecated)
extension FormValueTests {

    func testSingleForm() async throws {
        // Given
        let key = "title"
        let value = "foo"
        let property = FormValue(value, forKey: key)

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
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }
}
