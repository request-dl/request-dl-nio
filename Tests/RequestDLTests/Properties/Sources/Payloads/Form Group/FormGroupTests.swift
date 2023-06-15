/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable function_body_length
class FormGroupTests: XCTestCase {

    func testGroup_whenMultipleData() async throws {
        // Given
        let parts = (0..<10).map { _ in
            Data.randomData(length: (0...256).randomElement() ?? 256)
        }

        // When
        let resolved = try await resolve(TestProperty {
            FormGroup {
                PropertyForEach(parts.enumerated(), id: \.offset) {
                    Form(
                        name: "part\($0)",
                        data: $1
                    )
                }
            }
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

        XCTAssertEqual(parsed.items, partForms(parts))
    }

    func testGroup_whenMultipleDataWithFormGroup() async throws {
        // Given
        let parts1 = (0..<6).map { _ in
            Data.randomData(length: (0...256).randomElement() ?? 256)
        }

        let parts2 = (0..<3).map { _ in
            Data.randomData(length: (0...128).randomElement() ?? 128)
        }

        let parts3 = (0..<9).map { _ in
            Data.randomData(length: (0...64).randomElement() ?? 64)
        }

        // When
        let resolved = try await resolve(TestProperty {
            FormGroup {
                FormGroup {
                    PropertyForEach(parts1.enumerated(), id: \.offset) {
                        Form(
                            name: "part1.\($0)",
                            data: $1
                        )
                    }
                }

                FormGroup {
                    PropertyForEach(parts2.enumerated(), id: \.offset) {
                        Form(
                            name: "part2.\($0)",
                            data: $1
                        )
                    }
                }

                FormGroup {
                    PropertyForEach(parts3.enumerated(), id: \.offset) {
                        Form(
                            name: "part3.\($0)",
                            data: $1
                        )
                    }
                }
            }
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

        XCTAssertEqual(parsed.items, (
            partForms(parts1, prefix: "part1.") +
            partForms(parts2, prefix: "part2.") +
            partForms(parts3, prefix: "part3.")
        ))
    }

    func testGroup_whenChunkSize() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 256)
        let chunkSize = 64

        // When
        let resolved = try await resolve(TestProperty {
            FormGroup {
                Form(
                    name: name,
                    data: data
                )
            }
            .payloadChunkSize(chunkSize)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let buffers = try await resolved.request.body?.buffers() ?? []
        let builtData = buffers.compactMap { $0.getData() }.reduce(Data(), +)
        let totalBytes = builtData.count

        // Then
        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: totalBytes, by: chunkSize).map {
                let upperBound = $0 + chunkSize
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

    func testGroup_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = FormGroup {
            Form(
                name: "foo",
                data: .randomData(length: 64)
            )
        }

        // Then
        try await assertNever(property.body)
    }
}

extension FormGroupTests {

    func partForms(_ parts: [Data], prefix: String = "part") -> [PartForm] {
        parts.enumerated().map { offset, data in
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(prefix)\(offset)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        }
    }
}
// swiftlint:enable function_body_length
