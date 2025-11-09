/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

// swiftlint:disable file_length type_body_length
struct PayloadTests {

    @Test
    func payload_whenInitJSON() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(try data == JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    @Test
    func payload_whenInitJSONArray() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(try data == JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    @Test
    func payload_whenInitJSONWithCustomType() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == [String(customType)]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(try data == JSONSerialization.data(
            withJSONObject: json,
            options: .sortedKeys
        ))
    }

    @Test
    func payload_whenInitEncodable() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try data.map {
                try decoder.decode(PayloadMock.self, from: $0)
            } == mock
        )
    }

    @Test
    func payload_whenInitEncodableWithCustomType() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == [String(customType)]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try data.map {
                try decoder.decode(PayloadMock.self, from: $0)
            } == mock
        )
    }

    @Test
    func payload_whenInitString() async throws {
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
        #expect(
            resolved1.request.headers["Content-Type"] == ["text/plain; charset=UTF-8"]
        )

        #expect(
            resolved1.request.headers["Content-Length"] == (data1?.count).map { [String($0)] }
        )

        #expect(
            resolved2.request.headers["Content-Type"] == ["text/plain; charset=UTF-16"]
        )

        #expect(
            resolved2.request.headers["Content-Length"] == (data2?.count).map { [String($0)] }
        )

        #expect(data1 == verbatim.data(using: .utf8))
        #expect(data2 == verbatim.data(using: .utf16))
    }

    @Test
    func payload_whenInitStringWithCustomType() async throws {
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
        #expect(
            resolved1.request.headers["Content-Type"] == ["text/plain+request-dl; charset=UTF-8"]
        )

        #expect(
            resolved1.request.headers["Content-Length"] == (data1?.count).map { [String($0)] }
        )

        #expect(
            resolved2.request.headers["Content-Type"] == ["text/plain+request-dl; charset=UTF-16"]
        )

        #expect(
            resolved2.request.headers["Content-Length"] == (data2?.count).map { [String($0)] }
        )

        #expect(data1 == verbatim.data(using: .utf8))
        #expect(data2 == verbatim.data(using: .utf16))
    }

    @Test
    func payload_whenInitData() async throws {
        // Given
        let data = Data.randomData(length: 1_024 * 1_024)

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
        })

        let builtData = try await resolved.request.body?.data()

        // Then
        #expect(
            resolved.request.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitDataWithCustomType() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == [String(contentType)]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitURL() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitURLWithCustomType() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == [String(contentType)]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = Payload(data: Data())

        // Then
        try await assertNever(property.body)
    }
}
// swiftlint:enable type_body_length

// MARK: - Form URL encoded tests

extension PayloadTests {

    @Test
    func payload_whenGETInitJSONWithURLEncoded() async throws {
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
        #expect(data == nil)
        #expect(resolved.request.headers["Content-Type"] == nil)
        #expect(resolved.request.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.request.queries) == Set(json.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    $0.build()
                }
            })
        )
    }

    @Test
    func payload_whenPOSTInitJSONWithURLEncodedCharsetUTF16() async throws {
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
        #expect(resolved.request.queries.isEmpty)

        #expect(
            resolved.request.headers["Content-Type"] == ["application/x-www-form-urlencoded; charset=UTF-16"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try Set(components) == Set(json.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    let query = $0.build()
                    return "\(query.name)=\(query.value)"
                }
            })
        )
    }

    @Test
    func payload_whenGETInitEncodableWithURLEncoded() async throws {
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
        #expect(json != nil)
        #expect(data == nil)
        #expect(resolved.request.headers["Content-Type"] == nil)
        #expect(resolved.request.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.request.queries) == Set(json?.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    $0.build()
                }
            } ?? [])
        )
    }

    @Test
    func payload_whenPOSTInitEncodableWithURLEncodedCharsetUTF16() async throws {
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
        #expect(json != nil)

        #expect(resolved.request.queries.isEmpty)

        #expect(
            resolved.request.headers["Content-Type"] == ["application/x-www-form-urlencoded; charset=UTF-16"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try Set(components) == Set(json?.reduce([]) {
                try $0 + URLEncoder().encode($1.value, forKey: $1.key).map {
                    let query = $0.build()
                    return "\(query.name)=\(query.value)"
                }
            } ?? [])
        )
    }

    @Test
    func payload_whenGETInitDataWithURLEncoded() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/x-www-form-urlencoded"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        #expect(resolvedData == data)

        #expect(resolved.request.url == "https://www.apple.com")
    }
}

// MARK: - Others tests

extension PayloadTests {

    @Test
    func payload_whenInitDataWithChunkSize() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [String(data.count)]
        )

        let totalBytes = data.count

        #expect(
            buffers.compactMap { $0.getData() } == stride(from: .zero, to: data.count, by: chunkSize).map {
                let upperBound = $0 + chunkSize
                return data[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )
    }

    @Test
    func payload_whenInvalidJSONObject() async throws {
        // Given
        let jsonObject: Any = { () in }
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
        #expect(encodingError?.context == .invalidJSONObject)
    }

    @Test
    func payload_whenEmptyPayload() async throws {
        // Given
        let data = Data()

        // When
        let resolved = try await resolve(TestProperty {
            Payload(data: data)
        })

        let buffers = try await resolved.request.body?.buffers() ?? []

        // Then
        #expect(
            resolved.request.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(resolved.request.headers["Content-Length"] == nil)

        #expect(buffers.resolveData().reduce(Data(), +) == data)
    }
}

// MARK: - Deprecated

extension PayloadTests {

    @Test
    func deprecated_whenInitDataWithPartLength() async throws {
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
        #expect(
            resolved.request.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.request.headers["Content-Length"] == [
                String(data.count)
            ]
        )

        let totalBytes = data.count

        #expect(
            buffers.compactMap { $0.getData() } == stride(from: .zero, to: data.count, by: chunkSize).map {
                let upperBound = $0 + chunkSize
                return data[$0 ..< (upperBound <= totalBytes ? upperBound : totalBytes)]
            }
        )
    }
}
// swiftlint:enable file_length
