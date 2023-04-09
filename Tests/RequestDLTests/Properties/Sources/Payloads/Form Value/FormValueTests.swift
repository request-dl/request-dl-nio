/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class FormValueTests: XCTestCase {

    func testSingleForm() async throws {
        // Given
        let key = "title"
        let value = "foo"
        let property = FormValue(value, forKey: key)

        // When
        let (_, request) = try await resolve(TestProperty(property))

        let contentTypeHeader = request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testNeverBody() async throws {
        // Given
        let property = FormValue("123", forKey: "key")

        // Then
        try await assertNever(property.body)
    }
}
