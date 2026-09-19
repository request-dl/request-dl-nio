//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct FormGroupTests {

    @Test
    func group_whenMultipleData() async throws {
        // Given
        let parts = await Data.randomParts(10) { _ in
            await Data.randomData(length: (0...256).randomElement() ?? 256)
        }

        // When
        let resolved = try await resolve(
            TestProperty {
                FormGroup {
                    PropertyForEach(parts.enumerated(), id: \.offset) {
                        Form(
                            name: "part\($0)",
                            data: $1
                        )
                    }
                }
            }
        )

        let parser = try await MultipartFormParser(resolved.requestConfiguration)
        let parsed = try await parser.parse()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "multipart/form-data; boundary=\"\(parsed.boundary)\""
            ]
        )

        let resolvedContentLength = await parser.buffers.async.map {
            await $0.estimatedBytes
        }.reduce(.zero, +)

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [
                String(resolvedContentLength)
            ]
        )

        #expect(parsed.items == partForms(parts))
    }

    @Test
    func group_whenMultipleDataWithFormGroup() async throws {
        // Given
        let parts1 = await Data.randomParts(6) { _ in
            await Data.randomData(length: (0...256).randomElement() ?? 256)
        }

        let parts2 = await Data.randomParts(3) { _ in
            await Data.randomData(length: (0...128).randomElement() ?? 128)
        }

        let parts3 = await Data.randomParts(9) { _ in
            await Data.randomData(length: (0...64).randomElement() ?? 64)
        }

        // When
        let resolved = try await resolve(
            TestProperty {
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
            }
        )

        let parser = try await MultipartFormParser(resolved.requestConfiguration)
        let parsed = try await parser.parse()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "multipart/form-data; boundary=\"\(parsed.boundary)\""
            ]
        )

        let resolvedContentLength = await parser.buffers.async.map {
            await $0.estimatedBytes
        }.reduce(.zero, +)

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [
                String(resolvedContentLength)
            ]
        )

        #expect(
            parsed.items
                == (partForms(parts1, prefix: "part1.") + partForms(parts2, prefix: "part2.")
                    + partForms(parts3, prefix: "part3."))
        )
    }

    @Test
    func group_whenChunkSize() async throws {
        // Given
        let name = "foo"
        let data = await Data.randomData(length: 256)
        let chunkSize = 64

        // When
        let resolved = try await resolve(
            TestProperty {
                FormGroup {
                    Form(
                        name: name,
                        data: data
                    )
                }
                .payloadChunkSize(chunkSize)
            }
        )

        let parser = try await MultipartFormParser(resolved.requestConfiguration)
        let parsed = try await parser.parse()

        let buffers = try await resolved.requestConfiguration.body?.buffers() ?? []
        let builtData = await buffers.async.compactMap { await $0.getData() }.reduce(Data(), +)
        let totalBytes = builtData.count

        // Then
        let resolvedData = try await Array(buffers.async.compactMap { await $0.getData() })
        #expect(
            resolvedData
                == stride(from: .zero, to: totalBytes, by: chunkSize).map {
                    let upperBound = $0 + chunkSize
                    return builtData[$0..<(upperBound <= totalBytes ? upperBound : totalBytes)]
                }
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "multipart/form-data; boundary=\"\(parsed.boundary)\""
            ]
        )

        let resolvedContentLength = await parser.buffers.async.map {
            await $0.estimatedBytes
        }.reduce(.zero, +)

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [
                String(resolvedContentLength)
            ]
        )

        #expect(
            parsed.items == [
                PartForm(
                    headers: HTTPHeaders([
                        ("Content-Disposition", "form-data; name=\"\(name)\""),
                        ("Content-Type", "application/octet-stream"),
                        ("Content-Length", String(data.count)),
                    ]),
                    contents: data
                )
            ]
        )
    }

    @Test
    func group_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = FormGroup {
            AsyncProperty {
                Form(
                    name: "foo",
                    data: await .randomData(length: 64)
                )
            }
        }

        // Then
        try await assertNever(property.body)
    }

    @Test
    func group_whenNameOrFilenameContainsQuoteOrCRLF_escapesInsteadOfInjectingHeaders() async throws {
        // Given
        let name = "foo\"\r\nContent-Type: text/html\r\n\r\n<script>evil()</script>"
        let filename = "bar\".txt\r\nContent-Disposition: form-data; name=\"admin"
        let data = await Data.randomData(length: 32)

        // When
        let resolved = try await resolve(
            TestProperty {
                FormGroup {
                    Form(
                        name: name,
                        filename: filename,
                        contentType: .octetStream,
                        data: data
                    )
                }
            }
        )

        let parser = try await MultipartFormParser(resolved.requestConfiguration)
        let parsed = try await parser.parse()

        // Then
        let escapedName = "foo%22%0D%0AContent-Type: text/html%0D%0A%0D%0A<script>evil()</script>"
        let escapedFilename = "bar%22.txt%0D%0AContent-Disposition: form-data; name=%22admin"
        let expectedContentDisposition =
            "form-data; name=\"\(escapedName)\"; filename=\"\(escapedFilename)\""

        let item = try #require(parsed.items.first)

        #expect(parsed.items.count == 1)
        #expect(item.headers["Content-Disposition"] == [expectedContentDisposition])
        #expect(item.headers["Content-Type"] == ["application/octet-stream"])
        #expect(item.headers["Content-Length"] == [String(data.count)])
        #expect(item.contents == data)
    }

    @Test
    func group_whenEmptyContent() async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                FormGroup {}
            }
        )

        let data = try await resolved.requestConfiguration.body?.data() ?? Data()

        // Then
        #expect(data.isEmpty)

        #expect(resolved.requestConfiguration.headers["Content-Type"] == nil)

        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)
    }
}

extension FormGroupTests {

    func partForms(_ parts: [Data], prefix: String = "part") -> [PartForm] {
        parts.enumerated().map { offset, data in
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(prefix)\(offset)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count)),
                ]),
                contents: data
            )
        }
    }
}
