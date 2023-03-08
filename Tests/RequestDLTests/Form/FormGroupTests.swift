//
//  Form.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest
@testable import RequestDL

final class FormGroupTests: XCTestCase {

    func testSingleForm() async throws {
        // Given
        let key = "index"
        let value = 1

        let property = FormGroup {
            FormValue(value, forKey: key)
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            request.httpBody ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data("\(value)".utf8))
    }

    /*
    func testMultipleForm() async throws {
        // Given
        let key1 = "index"
        let value1 = 1

        let key2 = "template_image"
        let value2 = try ResourceFile("template_image").data()
        let fileName2 = "image.jpeg"
        let contentType2: ContentType = .jpeg

        let key3 = "template_document"
        let resourceFile3 = ResourceFile("template_document")
        let value3 = try resourceFile3.url()

        let property = FormGroup {
            FormValue(value1, forKey: key1)

            FormData(
                value2,
                forKey: key2,
                fileName: fileName2,
                type: contentType2
            )

            FormFile(
                value3,
                forKey: key3,
                fileName: nil,
                type: nil
            )
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            request.httpBody ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 3)

        // Then: - Property Index 0
        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key1)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data("\(value1)".utf8))

        // Then: - Property Index 1
        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"\(key2)\"; filename=\"\(fileName2)\""
        )

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Type"],
            contentType2.rawValue
        )

        XCTAssertEqual(
            multipartForm.items[1].contents,
            value2
        )

        // Then: - Property Index 2
        XCTAssertEqual(
            multipartForm.items[2].headers["Content-Disposition"],
            "form-data; name=\"\(key3)\"; filename=\"\(try resourceFile3.url().lastPathComponent)\""
        )

        XCTAssertEqual(
            multipartForm.items[2].headers["Content-Type"],
            ContentType.pdf.rawValue
        )

        XCTAssertEqual(
            multipartForm.items[2].contents,
            try resourceFile3.data()
        )
    }
     */

    func testCollision() async throws {
        // Given
        let key = "index"
        let value1 = "123"
        let value2 = 124

        let property = FormGroup {
            FormValue(value1, forKey: key)
            FormValue(value2, forKey: key)
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        let contentTypeHeader = request.value(forHTTPHeaderField: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            request.httpBody ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 2)

        XCTAssertEqual(multipartForm.items[0].contents, Data(value1.utf8))

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[1].contents, Data("\(value2)".utf8))

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )
    }

    func testNeverBody() async throws {
        // Given
        let type = FormGroup<EmptyProperty>.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
