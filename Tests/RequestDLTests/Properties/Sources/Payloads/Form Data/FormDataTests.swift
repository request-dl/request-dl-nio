/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class FormDataTests: XCTestCase {

    func testForm_whenInitDataEmptyFilename() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                data,
                forKey: name,
                type: .octetStream
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
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenInitDataFilename() async throws {
        // Given
        let name = "foo"
        let filename = "bar"
        let data = Data.randomData(length: 1_024)
        let contentType = ContentType.text

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                data,
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
                    ("Content-Type", "text/plain"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenInitEncodableEmptyFilename() async throws {
        // Given
        let name = "some_name"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                mock,
                forKey: name,
                encoder: encoder
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try encoder.encode(mock)

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items.map(\.headers), [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\""),
                ("Content-Type", "application/json"),
                ("Content-Length", String(data.count))
            ])
        ])

        XCTAssertEqual(
            try parsed.items.map {
                try decoder.decode(PayloadMock.self, from: $0.contents)
            },
            [mock]
        )
    }

    func testForm_whenInitEncodableFilename() async throws {
        // Given
        let name = "some_name"
        let filename = "bar"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                mock,
                forKey: name,
                fileName: filename,
                encoder: encoder
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try encoder.encode(mock)

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        XCTAssertEqual(parsed.items.map(\.headers), [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", "application/json"),
                ("Content-Length", String(data.count))
            ])
        ])

        XCTAssertEqual(
            try parsed.items.map {
                try decoder.decode(PayloadMock.self, from: $0.contents)
            },
            [mock]
        )
    }

    func testForm_whenInitDataEmptyFilenamePartLength() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)
        let partLength = 64

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                data,
                forKey: name,
                type: .octetStream
            )
            .payloadPartLength(partLength)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let buffers = try await resolved.request.body?.buffers() ?? []
        let builtData = buffers.compactMap { $0.getData() }.reduce(Data(), +)
        let totalBytes = builtData.count

        // Then
        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: totalBytes, by: partLength).map {
                let upperBound = $0 + partLength
                return builtData[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
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
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    func testForm_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = FormData(
            Data(),
            forKey: "foo",
            type: .octetStream
        )

        // Then
        try await assertNever(property.body)
    }
}
