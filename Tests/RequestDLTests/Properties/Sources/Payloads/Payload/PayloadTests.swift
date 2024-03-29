/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable file_length type_body_length
class PayloadTests: XCTestCase {

    func testPayload_whenInitJSON() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2]
        ]

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                json,
                options: .sortedKeys
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/json"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(data, try JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    func testPayload_whenInitJSONArray() async throws {
        // Given
        let json: [Any] = [
            ["foo", "bar"],
            ["user": ["name": "olaf"]],
            [0, 1, 2]
        ]

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                json,
                options: .sortedKeys
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/json"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(data, try JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    func testPayload_whenInitJSONWithCustomType() async throws {
        // Given
        let json: [String: Any] = [:]
        let customType = ContentType("application/json+request-dl")

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                json,
                options: .sortedKeys,
                contentType: customType
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            [String(customType)]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(data, try JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    func testPayload_whenInitEncodable() async throws {
        // Given
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                mock,
                encoder: encoder
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/json"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            try data.map {
                try decoder.decode(PayloadMock.self, from: $0)
            },
            mock
        )
    }

    func testPayload_whenInitEncodableWithCustomType() async throws {
        // Given
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let customType = ContentType("application/json+request-dl")

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                mock,
                encoder: encoder,
                contentType: customType
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            [String(customType)]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            try data.map {
                try decoder.decode(PayloadMock.self, from: $0)
            },
            mock
        )
    }

    func testPayload_whenInitString() async throws {
        // Given
        let verbatim = "Hello world!"

        // When
        let resolved1 = try await resolve(TestProperty {
            Payload(verbatim: verbatim)
        })

        let resolved2 = try await resolve(TestProperty {
            Payload(verbatim: verbatim)
                .charset(.utf16)
        })

        let data1 = try await resolved1.request.body?.data()
        let data2 = try await resolved2.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved1.request.headers["Content-Type"],
            ["text/plain; charset=UTF-8"]
        )

        XCTAssertEqual(
            resolved1.request.headers["Content-Length"],
            (data1?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            resolved2.request.headers["Content-Type"],
            ["text/plain; charset=UTF-16"]
        )

        XCTAssertEqual(
            resolved2.request.headers["Content-Length"],
            (data2?.count).map { [String($0)] }
        )

        XCTAssertEqual(data1, verbatim.data(using: .utf8))
        XCTAssertEqual(data2, verbatim.data(using: .utf16))
    }

    func testPayload_whenInitStringWithCustomType() async throws {
        // Given
        let verbatim = "Hello world!"
        let customType = ContentType("text/plain+request-dl")

        // When
        let resolved1 = try await resolve(TestProperty {
            Payload(
                verbatim: verbatim,
                contentType: customType
            )
        })

        let resolved2 = try await resolve(TestProperty {
            Payload(
                verbatim: verbatim,
                contentType: customType
            )
            .charset(.utf16)
        })

        let data1 = try await resolved1.request.body?.data()
        let data2 = try await resolved2.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved1.request.headers["Content-Type"],
            ["text/plain+request-dl; charset=UTF-8"]
        )

        XCTAssertEqual(
            resolved1.request.headers["Content-Length"],
            (data1?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            resolved2.request.headers["Content-Type"],
            ["text/plain+request-dl; charset=UTF-16"]
        )

        XCTAssertEqual(
            resolved2.request.headers["Content-Length"],
            (data2?.count).map { [String($0)] }
        )

        XCTAssertEqual(data1, verbatim.data(using: .utf8))
        XCTAssertEqual(data2, verbatim.data(using: .utf16))
    }

    func testPayload_whenInitData() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
        })

        let builtData = try await resolved.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        XCTAssertEqual(builtData, data)
    }

    func testPayload_whenInitDataWithCustomType() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)
        let contentType = ContentType("application/octet-stream+request-dl")

        // When
        let resolved = try await resolve(TestProperty {
            Payload(
                data: data,
                contentType: contentType
            )
        })

        let builtData = try await resolved.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            [String(contentType)]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        XCTAssertEqual(builtData, data)
    }

    func testPayload_whenInitURL() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            Payload(
                url: url,
                contentType: .octetStream
            )
        })

        let builtData = try await resolved.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        XCTAssertEqual(builtData, data)
    }

    func testPayload_whenInitURLWithCustomType() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)
        let contentType = ContentType("application/octet-stream+request-dl")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            Payload(
                url: url,
                contentType: contentType
            )
        })

        let builtData = try await resolved.request.body?.data()

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            [String(contentType)]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        XCTAssertEqual(builtData, data)
    }

    func testPayload_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = Payload(data: Data())

        // Then
        try await assertNever(property.body)
    }
}
// swiftlint:enable type_body_length

// MARK: - Form URL encoded tests

extension PayloadTests {

    func testPayload_whenGETInitJSONWithURLEncoded() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2]
        ]

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                json,
                options: .fragmentsAllowed,
                contentType: .formURLEncoded
            )
        })

        let data = try await resolved.request.body?.data()

        // When
        XCTAssertNil(data)
        XCTAssertNil(resolved.request.headers["Content-Type"])
        XCTAssertNil(resolved.request.headers["Content-Length"])

        XCTAssertEqual(
            Set(resolved.request.queries),
            try Set(json.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    $0.build()
                }
            })
        )
    }

    func testPayload_whenPOSTInitJSONWithURLEncodedCharsetUTF16() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2]
        ]

        // Then
        let resolved = try await resolve(TestProperty {
            RequestMethod(.post)

            Payload(
                json,
                options: .fragmentsAllowed,
                contentType: .formURLEncoded
            )
            .charset(.utf16)
        })

        let data = try await resolved.request.body?.data()

        let components = data.flatMap {
            String(data: $0, encoding: .utf16)
        }?.split(separator: "&") ?? []

        // When
        XCTAssertTrue(resolved.request.queries.isEmpty)

        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/x-www-form-urlencoded; charset=UTF-16"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            Set(components),
            try Set(json.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    let query = $0.build()
                    return "\(query.name)=\(query.value)"
                }
            })
        )
    }

    func testPayload_whenGETInitEncodableWithURLEncoded() async throws {
        // Given
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // Then
        let resolved = try await resolve(TestProperty {
            Payload(
                mock,
                encoder: encoder,
                contentType: .formURLEncoded
            )
        })

        let data = try await resolved.request.body?.data()

        let json = try JSONSerialization.jsonObject(
            with: encoder.encode(mock),
            options: .fragmentsAllowed
        ) as? [String: Any]

        // When
        XCTAssertNotNil(json)
        XCTAssertNil(data)
        XCTAssertNil(resolved.request.headers["Content-Type"])
        XCTAssertNil(resolved.request.headers["Content-Length"])

        XCTAssertEqual(
            Set(resolved.request.queries),
            try Set(json?.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    $0.build()
                }
            } ?? [])
        )
    }

    func testPayload_whenPOSTInitEncodableWithURLEncodedCharsetUTF16() async throws {
        // Given
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // Then
        let resolved = try await resolve(TestProperty {
            RequestMethod(.post)

            Payload(
                mock,
                encoder: encoder,
                contentType: .formURLEncoded
            )
            .charset(.utf16)
        })

        let data = try await resolved.request.body?.data()

        let components = data.flatMap {
            String(data: $0, encoding: .utf16)
        }?.split(separator: "&") ?? []

        let json = try JSONSerialization.jsonObject(
            with: encoder.encode(mock),
            options: .fragmentsAllowed
        ) as? [String: Any]

        // When
        XCTAssertNotNil(json)

        XCTAssertTrue(resolved.request.queries.isEmpty)

        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/x-www-form-urlencoded; charset=UTF-16"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            (data?.count).map { [String($0)] }
        )

        XCTAssertEqual(
            Set(components),
            try Set(json?.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    let query = $0.build()
                    return "\(query.name)=\(query.value)"
                }
            } ?? [])
        )
    }

    func testPayload_whenGETInitDataWithURLEncoded() async throws {
        // Given
        let data = Data.randomData(length: 1_024)

        // Then
        let resolved = try await resolve(TestProperty {
            RequestMethod(.get)

            Payload(
                data: data,
                contentType: .formURLEncoded
            )
        })

        let resolvedData = try await resolved.request.body?.data()

        // When
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/x-www-form-urlencoded"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        XCTAssertEqual(resolvedData, data)

        XCTAssertEqual(resolved.request.url, "https://www.apple.com")
    }
}

// MARK: - Others tests

extension PayloadTests {

    func testPayload_whenInitDataWithChunkSize() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)
        let chunkSize = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
                .payloadChunkSize(chunkSize)
        })

        let buffers = try await resolved.request.body?.buffers() ?? []

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        let totalBytes = data.count

        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: data.count, by: chunkSize).map {
                let upperBound = $0 + chunkSize
                return data[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )
    }

    func testPayload_whenInvalidJSONObject() async throws {
        // Given
        let jsonObject: Any = { () -> Void in }
        var encodingError: EncodingPayloadError?

        // When
        do {
            _ = try await resolve(TestProperty {
                Payload(jsonObject)
            })
        } catch let error as EncodingPayloadError {
            encodingError = error
        }

        // Then
        XCTAssertEqual(encodingError?.context, .invalidJSONObject)
    }

    func testPayload_whenEmptyPayload() async throws {
        // Given
        let data = Data()

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
        })

        let buffers = try await resolved.request.body?.buffers() ?? []

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertNil(resolved.request.headers["Content-Length"])

        XCTAssertEqual(buffers.resolveData().reduce(Data(), +), data)
    }
}

// MARK: - Deprecated

@available(*, deprecated)
extension PayloadTests {

    func testDeprecated_whenInitDataWithPartLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)
        let chunkSize = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
                .payloadPartLength(chunkSize)
        })

        let buffers = try await resolved.request.body?.buffers() ?? []

        // Then
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/octet-stream"]
        )

        XCTAssertEqual(
            resolved.request.headers["Content-Length"],
            [String(data.count)]
        )

        let totalBytes = data.count

        XCTAssertEqual(
            buffers.compactMap { $0.getData() },
            stride(from: .zero, to: data.count, by: chunkSize).map {
                let upperBound = $0 + chunkSize
                return data[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )
    }
}
// swiftlint:enable file_length
