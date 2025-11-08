/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

// swiftlint:disable file_length type_body_length function_body_length
struct FormTests {

    // MARK: - Init with Data

    @Test
    func form_whenInitData() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                data: data
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
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

    @Test
    func form_whenInitDataWithFilename() async throws {
        // Given
        let name = "foo"
        let filename = "bar.raw"
        let data = Data.randomData(length: 1_024)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                data: data
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
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

    @Test
    func form_whenInitDataWithHeaders() async throws {
        // Given
        let name = "foo"
        let filename = "bar.raw"
        let data = Data.randomData(length: 1_024)
        let headers = [
            ("Accept-Language", "en-US"),
            ("Content-Encoding", "gzip")
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                data: data,
                headers: {
                    PropertyForEach(headers, id: \.0) {
                        CustomHeader(name: $0, value: $1)
                    }
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count))
                ] + headers),
                contents: data
            )
        ])
    }

    // MARK: - Init with URL

    @Test
    func form_whenInitURL() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form.file.\(UUID())")
            .appendingPathExtension("raw")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                contentType: .pdf,
                url: url
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(url.lastPathComponent)\""),
                    ("Content-Type", "application/pdf"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    @Test
    func form_whenInitURLWithFilename() async throws {
        // Given
        let name = "foo"
        let filename = "bar.raw"
        let data = Data.randomData(length: 1_024)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form.file.\(UUID())")
            .appendingPathExtension("raw")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: .pdf,
                url: url
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                    ("Content-Type", "application/pdf"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])

    }

    @Test
    func form_whenInitURLWithHeaders() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)
        let headers = [
            ("Accept-Language", "en-US"),
            ("Content-Encoding", "gzip")
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form.file.\(UUID())")
            .appendingPathExtension("raw")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                contentType: .pdf,
                url: url,
                headers: {
                    PropertyForEach(headers, id: \.0) {
                        CustomHeader(name: $0, value: $1)
                    }
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(url.lastPathComponent)\""),
                    ("Content-Type", "application/pdf"),
                    ("Content-Length", String(data.count))
                ] + headers),
                contents: data
            )
        ])
    }

    // MARK: - Init with String

    @Test
    func form_whenInitString() async throws {
        // Given
        let name = "foo"
        let verbatim = "Hello world!"

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                verbatim: verbatim
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", String(verbatim.utf8.count))
                ]),
                contents: Data(verbatim.utf8)
            )
        ])
    }

    @Test
    func form_whenInitStringCharsetUTF16() async throws {
        // Given
        let name = "foo"
        let verbatim = "Hello world!"

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                verbatim: verbatim
            )
            .charset(.utf16)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = verbatim.data(using: .utf16) ?? Data()

        // Then
        #expect(data.count != .zero)

        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "text/plain; charset=UTF-16"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    @Test
    func form_whenInitStringWithFilename() async throws {
        // Given
        let name = "foo"
        let filename = "bar"
        let verbatim = "Hello world!"

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                verbatim: verbatim
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", String(verbatim.utf8.count))
                ]),
                contents: Data(verbatim.utf8)
            )
        ])
    }

    @Test
    func form_whenInitStringWithHeaders() async throws {
        // Given
        let name = "foo"
        let verbatim = "Hello world!"
        let headers = [
            ("Accept-Language", "en-US"),
            ("Content-Encoding", "gzip")
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                verbatim: verbatim,
                headers: {
                    PropertyForEach(headers, id: \.0) {
                        CustomHeader(name: $0, value: $1)
                    }
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "text/plain; charset=UTF-8"),
                    ("Content-Length", String(verbatim.utf8.count))
                ] + headers),
                contents: Data(verbatim.utf8)
            )
        ])
    }

    // MARK: - Init with Encodable

    @Test
    func form_whenInitEncodable() async throws {
        // Given
        let name = "_name"
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
            Form(
                name: name,
                value: mock,
                encoder: encoder
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try encoder.encode(mock)

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\""),
                ("Content-Type", "application/json"),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            try parsed.items.map {
                try decoder.decode(PayloadMock.self, from: $0.contents)
            },
            [mock]
        )
    }

    @Test
    func form_whenInitEncodableWithFilename() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let contentType = ContentType("application/json+request-dl")
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
            Form(
                name: name,
                filename: filename,
                contentType: contentType,
                value: mock,
                encoder: encoder
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try encoder.encode(mock)

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", String(contentType)),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            try parsed.items.map {
                try decoder.decode(PayloadMock.self, from: $0.contents)
            },
            [mock]
        )
    }

    @Test
    func form_whenInitEncodableWithHeaders() async throws {
        // Given
        let name = "_name"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )
        let headers = [
            ("Accept-Language", "en-US"),
            ("Content-Encoding", "gzip")
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                value: mock,
                encoder: encoder,
                headers: {
                    PropertyForEach(headers, id: \.0) {
                        CustomHeader(name: $0, value: $1)
                    }
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try encoder.encode(mock)

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\""),
                ("Content-Type", "application/json"),
                ("Content-Length", String(data.count))
            ] + headers)
        ])

        #expect(
            try parsed.items.map {
                try decoder.decode(PayloadMock.self, from: $0.contents)
            },
            [mock]
        )
    }

    @Test
    func form_whenInitEncodableURLEncoded() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: .formURLEncoded,
                value: mock,
                encoder: encoder
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let jsonData = try JSONEncoder().encode(mock)
        let json = try JSONSerialization.jsonObject(with: jsonData)

        let dictionary = try #require(json as? [AnyHashable: Any])

        let queries = try dictionary
            .reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: String(describing: $1.key))
            }
            .map { $0.build() }
            .joined()

        let data = Data(queries.utf8)

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8"),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            parsed.items.map { $0.contents.queries(using: .utf8) },
            [data.queries(using: .utf8)]
        )
    }

    @Test
    func form_whenInitEncodableURLEncodedUTF16() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: .formURLEncoded,
                value: mock,
                encoder: encoder
            )
            .charset(.utf16)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let jsonData = try JSONEncoder().encode(mock)
        let json = try JSONSerialization.jsonObject(with: jsonData)

        let dictionary = try #require(json as? [AnyHashable: Any])

        let queries = try dictionary
            .reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: String(describing: $1.key))
            }
            .map { $0.build() }
            .joined()

        let data = queries.data(using: .utf16) ?? Data()

        // Then
        #expect(data.count != .zero)

        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", "application/x-www-form-urlencoded; charset=UTF-16"),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            parsed.items.map { $0.contents.queries(using: .utf8) },
            [data.queries(using: .utf8)]
        )
    }

    // MARK: - Init with JSON

    @Test
    func form_whenInitJSON() async throws {
        // Given
        let name = "_name"
        let jsonObject: [AnyHashable: Any] = [
            "foo": "bar",
            "magic_numbers": [0, 1, 2]
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                jsonObject: jsonObject,
                options: .sortedKeys
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: .sortedKeys
        )

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/json"),
                    ("Content-Length", String(data.count))
                ]),
                contents: data
            )
        ])
    }

    @Test
    func form_whenInitJSONWithFilename() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let contentType = ContentType("application/json+request-dl")
        let jsonObject: [AnyHashable: Any] = [
            "foo": "bar",
            "magic_numbers": [0, 1, 2]
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: contentType,
                jsonObject: jsonObject,
                options: .sortedKeys
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: .sortedKeys
        )

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
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

    @Test
    func form_whenInitJSONWithHeaders() async throws {
        // Given
        let name = "_name"
        let jsonObject: [AnyHashable: Any] = [
            "foo": "bar",
            "magic_numbers": [0, 1, 2]
        ]
        let headers = [
            ("Accept-Language", "en-US"),
            ("Content-Encoding", "gzip")
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                jsonObject: jsonObject,
                options: .sortedKeys,
                headers: {
                    PropertyForEach(headers, id: \.0) {
                        CustomHeader(name: $0, value: $1)
                    }
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: .sortedKeys
        )

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/json"),
                    ("Content-Length", String(data.count))
                ] + headers),
                contents: data
            )
        ])
    }

    @Test
    func form_whenInitJSONURLEncoded() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let jsonObject: [AnyHashable: Any] = [
            "foo": "bar",
            "magic_numbers": [0, 1, 2]
        ]

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: .formURLEncoded,
                jsonObject: jsonObject
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let queries = try jsonObject
            .reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: String(describing: $1.key))
            }
            .map { $0.build() }
            .joined()

        let data = Data(queries.utf8)

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8"),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            parsed.items.map { $0.contents.queries(using: .utf8) },
            [data.queries(using: .utf8)]
        )
    }

    @Test
    func form_whenInitJSONWithURLEncodedUTF16() async throws {
        // Given
        let name = "_name"
        let filename = "foo.json"
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                filename: filename,
                contentType: .formURLEncoded,
                value: mock,
                encoder: encoder
            )
            .charset(.utf16)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let jsonData = try JSONEncoder().encode(mock)
        let json = try JSONSerialization.jsonObject(with: jsonData)

        let dictionary = try #require(json as? [AnyHashable: Any])

        let queries = try dictionary
            .reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: String(describing: $1.key))
            }
            .map { $0.build() }
            .joined()

        let data = queries.data(using: .utf16) ?? Data()

        // Then
        #expect(data.count != .zero)

        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items.map(\.headers) == [
            HTTPHeaders([
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(filename)\""),
                ("Content-Type", "application/x-www-form-urlencoded; charset=UTF-16"),
                ("Content-Length", String(data.count))
            ])
        ])

        #expect(
            parsed.items.map { $0.contents.queries(using: .utf8) },
            [data.queries(using: .utf8)]
        )
    }

    // MARK: - Others tests

    @Test
    func form_whenInitDataChunkSize() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 1_024)
        let chunkSize = 64

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                data: data
            )
            .payloadChunkSize(chunkSize)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        let buffers = try await resolved.request.body?.buffers() ?? []
        let builtData = buffers.compactMap { $0.getData() }.reduce(Data(), +)
        let totalBytes = builtData.count

        // Then
        #expect(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: totalBytes, by: chunkSize).map {
                let upperBound = $0 + chunkSize
                return builtData[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )

        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
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

    @Test
    func form_whenHeadersWithAddingStrategy() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 64)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                data: data,
                headers: {
                    CustomHeader(name: "Accept-Language", value: "en-US")
                    CustomHeader(name: "Accept-Language", value: "pt-BR")
                }
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count)),
                    ("Accept-Language", "en-US"),
                    ("Accept-Language", "pt-BR")
                ]),
                contents: data
            )
        ])
    }

    @Test
    func form_whenHeadersWithSettingStrategy() async throws {
        // Given
        let name = "foo"
        let data = Data.randomData(length: 64)

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                data: data,
                headers: {
                    CustomHeader(name: "Accept-Language", value: "en-US")
                    CustomHeader(name: "Accept-Language", value: "pt-BR")
                }
            )
            .headerStrategy(.setting)
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
            PartForm(
                headers: HTTPHeaders([
                    ("Content-Disposition", "form-data; name=\"\(name)\""),
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count)),
                    ("Accept-Language", "pt-BR")
                ]),
                contents: data
            )
        ])
    }

    @Test
    func form_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = Form(
            name: "foo",
            data: .randomData(length: 64)
        )

        // Then
        try await assertNever(property.body)
    }
}

extension FormTests {

    @Test
    func form_whenEmptyData() async throws {
        // Given
        let name = "foo"
        let data = Data()

        // When
        let resolved = try await resolve(TestProperty {
            Form(
                name: name,
                data: data
            )
        })

        let parser = try await MultipartFormParser(resolved.request)
        let parsed = try parser.parse()

        // Then
        #expect(
            resolved.request.headers["Content-Type"],
            ["multipart/form-data; boundary=\"\(parsed.boundary)\""]
        )

        #expect(
            resolved.request.headers["Content-Length"],
            [String(parser.buffers.lazy.map(\.estimatedBytes).reduce(.zero, +))]
        )

        #expect(parsed.items == [
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
}
// swiftlint:enable file_length type_body_length function_body_length
