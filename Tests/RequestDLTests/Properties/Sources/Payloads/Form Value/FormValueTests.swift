/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class FormValueTests: XCTestCase {

    func testForm_whenInitKeyValue() async throws {
        // Given
        let key = "Foo"
        let value = 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(key: key, value: value)
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
                    ("Content-Disposition", "form-data; name=\"\(key)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", "7")
                ]),
                contents: Data(String(value).utf8)
            )
        ])
    }

    func testForm_whenInitKeyValueUTF16() async throws {
        // Given
        let key = "Foo"
        let value = 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(key: key, value: value)
                .charset(.utf16)
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
                    ("Content-Disposition", "form-data; name=\"\(key)\""),
                    ("Content-Type", "text/plain; charset=UTF-16"),
                    ("Content-Length", "16")
                ]),
                contents: String(value).data(using: .utf16) ?? Data()
            )
        ])
    }

    func testForm_whenInitAnyAndKey() async throws {
        // Given
        let key = "Foo"
        let value = 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(value, forKey: key)
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
                    ("Content-Disposition", "form-data; name=\"\(key)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", "7")
                ]),
                contents: Data(String(value).utf8)
            )
        ])
    }

    func testForm_whenInitKeyValuePartLength() async throws {
        // Given
        let key = "Foo"
        let value = 1_024 * 1_024
        let partLength = 2

        // When
        let resolved = try await resolve(TestProperty {
            FormValue(key: key, value: value)
                .payloadPartLength(partLength)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let buffers = try await resolved.request.body?.buffers() ?? []
        let data = buffers.compactMap { $0.getData() }.reduce(Data(), +)
        let totalBytes = data.count

        // Then
        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: totalBytes, by: partLength).map {
                let upperBound = $0 + partLength
                return data[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
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
                    ("Content-Disposition", "form-data; name=\"\(key)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", "7")
                ]),
                contents: Data(String(value).utf8)
            )
        ])
    }
}
