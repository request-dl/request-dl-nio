//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.UUID
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
#endif

#if canImport(Darwin)
import class Foundation.JSONSerialization
#endif

struct PayloadTests {

    // `Payload(_:options:contentType:)` only exists on Darwin — it is the one factory that
    // takes `Any`, so it cannot avoid `JSONSerialization`, which is not part of
    // `FoundationEssentials`. The three tests below exist to cover that initializer
    // specifically, so unlike the rest of this file, they have no portable counterpart to fall
    // back to.
    #if canImport(Darwin)

    @Test
    func payload_whenInitJSON() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2],
        ]

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    json,
                    options: .sortedKeys
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try data
                == JSONSerialization.data(
                    withJSONObject: json,
                    options: .sortedKeys
                )
        )
    }

    @Test
    func payload_whenInitJSONArray() async throws {
        // Given
        let json: [Any] = [
            ["foo", "bar"],
            ["user": ["name": "olaf"]],
            [0, 1, 2],
        ]

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    json,
                    options: .sortedKeys
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try data
                == JSONSerialization.data(
                    withJSONObject: json,
                    options: .sortedKeys
                )
        )
    }

    @Test
    func payload_whenInitJSONWithCustomType() async throws {
        // Given
        let json: [String: Any] = [:]
        let customType = ContentType("application/json+request-dl")

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    json,
                    options: .sortedKeys,
                    contentType: customType
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [String(customType)]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try data
                == JSONSerialization.data(
                    withJSONObject: json,
                    options: .sortedKeys
                )
        )
    }

    #endif

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
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    mock,
                    encoder: encoder
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/json"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
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
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    mock,
                    encoder: encoder,
                    contentType: customType
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [String(customType)]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
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
        let resolved1 = try await resolve(
            TestProperty {
                Payload(verbatim: verbatim)
            }
        )

        let resolved2 = try await resolve(
            TestProperty {
                Payload(verbatim: verbatim)
                    .charset(.utf16)
            }
        )

        let data1 = try await resolved1.requestConfiguration.body?.data()
        let data2 = try await resolved2.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved1.requestConfiguration.headers["Content-Type"] == ["text/plain; charset=UTF-8"]
        )

        #expect(
            resolved1.requestConfiguration.headers["Content-Length"] == (data1?.count).map { [String($0)] }
        )

        #expect(
            resolved2.requestConfiguration.headers["Content-Type"] == ["text/plain; charset=UTF-16"]
        )

        #expect(
            resolved2.requestConfiguration.headers["Content-Length"] == (data2?.count).map { [String($0)] }
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
        let resolved1 = try await resolve(
            TestProperty {
                Payload(
                    verbatim: verbatim,
                    contentType: customType
                )
            }
        )

        let resolved2 = try await resolve(
            TestProperty {
                Payload(
                    verbatim: verbatim,
                    contentType: customType
                )
                .charset(.utf16)
            }
        )

        let data1 = try await resolved1.requestConfiguration.body?.data()
        let data2 = try await resolved2.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved1.requestConfiguration.headers["Content-Type"] == ["text/plain+request-dl; charset=UTF-8"]
        )

        #expect(
            resolved1.requestConfiguration.headers["Content-Length"] == (data1?.count).map { [String($0)] }
        )

        #expect(
            resolved2.requestConfiguration.headers["Content-Type"] == ["text/plain+request-dl; charset=UTF-16"]
        )

        #expect(
            resolved2.requestConfiguration.headers["Content-Length"] == (data2?.count).map { [String($0)] }
        )

        #expect(data1 == verbatim.data(using: .utf8))
        #expect(data2 == verbatim.data(using: .utf16))
    }

    @Test
    func payload_whenInitStringWithContentTypeAlreadyDeclaringCharset() async throws {
        // Given
        // `appending(charset:)` must not append a second `charset` parameter when the content
        // type the caller passed already declares one.
        let verbatim = "Hello world!"
        let customType = ContentType("text/plain; charset=ISO-8859-1")

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    verbatim: verbatim,
                    contentType: customType
                )
                .charset(.utf16)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["text/plain; charset=ISO-8859-1"]
        )
    }

    @Test
    func payload_whenInitData() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(data: data)
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitDataWithCustomType() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)
        let contentType = ContentType("application/octet-stream+request-dl")

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    data: data,
                    contentType: contentType
                )
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [String(contentType)]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitURL() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)

        let url =
            temporaryDirectoryURL
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    url: url,
                    contentType: .octetStream
                )
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitURLWithCustomType() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)
        let contentType = ContentType("application/octet-stream+request-dl")

        let url =
            temporaryDirectoryURL
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    url: url,
                    contentType: contentType
                )
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [String(contentType)]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        #expect(builtData == data)
    }

    @Test
    func payload_whenInitURLWithOffset() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)
        let offset = 1_024 * 256

        let url =
            temporaryDirectoryURL
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    url: url,
                    from: UInt64(offset),
                    contentType: .octetStream
                )
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count - offset)]
        )

        #expect(builtData == data[offset...])
    }

    @Test
    func payload_whenInitURLWithOffsetAtEndOfFile() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)

        let url =
            temporaryDirectoryURL
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }

        try data.write(to: url)

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    url: url,
                    from: UInt64(data.count),
                    contentType: .octetStream
                )
            }
        )

        let builtData = try await resolved.requestConfiguration.body?.data()

        // Then
        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)
        #expect(builtData == Data())
    }

    @Test
    func payload_whenInitURLWithOffsetPastEndOfFile() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)

        let url =
            temporaryDirectoryURL
            .appendingPathComponent("payload.\(UUID())")
            .appendingPathExtension(".raw")

        try await url.createPathIfNeeded()
        defer { url.scheduleRemoval() }

        try data.write(to: url)

        var offsetError: InvalidPayloadOffsetError?

        // When
        do {
            _ = try await resolve(
                TestProperty {
                    Payload(
                        url: url,
                        from: UInt64(data.count) + 1,
                        contentType: .octetStream
                    )
                }
            )
        } catch let error as InvalidPayloadOffsetError {
            offsetError = error
        }

        // Then
        #expect(offsetError?.offset == UInt64(data.count) + 1)
        #expect(offsetError?.availableBytes == data.count)
    }

    @Test
    func payload_whenBodyCalled_shouldBeNever() async throws {
        // Given
        let property = Payload(data: Data())

        // Then
        try await assertNever(property.body)
    }
}

// MARK: - Form URL encoded tests

extension PayloadTests {

    // `Payload(_:options:contentType:)` only exists on Darwin — same reason as the block at the
    // top of this file: it is the one factory that takes `Any`, so it cannot avoid
    // `JSONSerialization`, which is not part of `FoundationEssentials`.
    #if canImport(Darwin)

    @Test
    func payload_whenGETInitJSONWithURLEncoded() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2],
        ]

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    json,
                    options: .fragmentsAllowed,
                    contentType: .formURLEncoded
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(data == nil)
        #expect(resolved.requestConfiguration.headers["Content-Type"] == nil)
        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.requestConfiguration.queries)
                == Set(
                    json.reduce([]) {
                        try $0
                            + URLEncoder().encode($1.value, forKey: $1.key)
                    }
                )
        )
    }

    @Test
    func payload_whenPOSTInitJSONWithURLEncodedCharsetUTF16() async throws {
        // Given
        let json: [String: Any] = [
            "foo": "bar",
            "user": ["name": "olaf"],
            "magic_numbers": [0, 1, 2],
        ]

        // Then
        let resolved = try await resolve(
            TestProperty {
                RequestMethod(.post)

                Payload(
                    json,
                    options: .fragmentsAllowed,
                    contentType: .formURLEncoded
                )
                .charset(.utf16)
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        let components =
            data.flatMap {
                String(data: $0, encoding: .utf16)
            }?.split(separator: "&") ?? []

        // When
        #expect(resolved.requestConfiguration.queries.isEmpty)

        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "application/x-www-form-urlencoded; charset=UTF-16"
            ]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try Set(components)
                == Set(
                    json.reduce([]) {
                        try $0
                            + URLEncoder().encode($1.value, forKey: $1.key).map {
                                let query = $0
                                return "\(query.name)=\(query.value)"
                            }
                    }
                )
        )
    }

    @Test
    func payload_whenGETInitJSONArrayWithURLEncoded() async throws {
        // Given
        let json: [Any] = ["bar", "olaf", 42]

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    json,
                    options: .fragmentsAllowed,
                    contentType: .formURLEncoded
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(data == nil)
        #expect(resolved.requestConfiguration.headers["Content-Type"] == nil)
        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.requestConfiguration.queries)
                == Set(
                    json.enumerated().reduce([]) {
                        try $0 + URLEncoder().encode($1.element, forKey: String($1.offset))
                    }
                )
        )
    }

    @Test
    func payload_whenPOSTInitJSONArrayWithURLEncodedCharsetUTF16() async throws {
        // Given
        let json: [Any] = ["bar", "olaf", 42]

        // Then
        let resolved = try await resolve(
            TestProperty {
                RequestMethod(.post)

                Payload(
                    json,
                    options: .fragmentsAllowed,
                    contentType: .formURLEncoded
                )
                .charset(.utf16)
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        let components =
            data.flatMap {
                String(data: $0, encoding: .utf16)
            }?.split(separator: "&") ?? []

        // When
        #expect(resolved.requestConfiguration.queries.isEmpty)

        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "application/x-www-form-urlencoded; charset=UTF-16"
            ]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try Set(components)
                == Set(
                    json.enumerated().reduce([]) {
                        try $0
                            + URLEncoder().encode($1.element, forKey: String($1.offset)).map {
                                let query = $0
                                return "\(query.name)=\(query.value)"
                            }
                    }
                )
        )
    }

    #endif

    @Test
    func payload_whenGETInitEncodableWithURLEncoded() async throws {
        // Given
        let mock = PayloadMock(
            foo: "bar",
            date: Date()
        )

        let encoder = JSONEncoder()

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    mock,
                    encoder: encoder,
                    contentType: .formURLEncoded
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // `JSONValue` stands in for `JSONSerialization`'s `Any`, which is not part of
        // `FoundationEssentials`.
        guard case .object(let json) = try JSONDecoder().decode(Internals.JSONValue.self, from: encoder.encode(mock))
        else {
            Issue.record("Expected the mock to encode as a JSON object")
            return
        }

        // When
        #expect(data == nil)
        #expect(resolved.requestConfiguration.headers["Content-Type"] == nil)
        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.requestConfiguration.queries)
                == Set(
                    json.reduce([]) {
                        try $0
                            + URLEncoder().encode($1.value.unwrapped, forKey: $1.key)
                    }
                )
        )
    }

    @Test
    func payload_whenGETInitEncodableArrayWithURLEncoded() async throws {
        // Given
        let values = ["bar", "olaf", "42"]

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    values,
                    contentType: .formURLEncoded
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(data == nil)
        #expect(resolved.requestConfiguration.headers["Content-Type"] == nil)
        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)

        #expect(
            try Set(resolved.requestConfiguration.queries)
                == Set(
                    values.enumerated().reduce([]) {
                        try $0 + URLEncoder().encode($1.element, forKey: String($1.offset))
                    }
                )
        )
    }

    @Test
    func payload_whenGETInitEncodableFragmentWithURLEncoded() async throws {
        // Given
        // A top-level fragment (neither a JSON object nor a JSON array) cannot be exploded
        // into query items, so it is sent as an already-encoded body instead — the same
        // fallback a non-form-urlencoded content type takes.
        let value = "just-a-string"

        // Then
        let resolved = try await resolve(
            TestProperty {
                Payload(
                    value,
                    contentType: .formURLEncoded
                )
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()
        let expectedData = try JSONEncoder().encode(value)

        // When
        #expect(resolved.requestConfiguration.queries.isEmpty)
        #expect(data == expectedData)
        #expect(resolved.requestConfiguration.headers["Content-Type"] == [String(ContentType.formURLEncoded)])
        #expect(resolved.requestConfiguration.headers["Content-Length"] == [String(expectedData.count)])
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
        let resolved = try await resolve(
            TestProperty {
                RequestMethod(.post)

                Payload(
                    mock,
                    encoder: encoder,
                    contentType: .formURLEncoded
                )
                .charset(.utf16)
            }
        )

        let data = try await resolved.requestConfiguration.body?.data()

        let components =
            data.flatMap {
                $0.decodedUTF16String()
            }?.split(separator: "&") ?? []

        // `JSONValue` stands in for `JSONSerialization`'s `Any`, which is not part of
        // `FoundationEssentials`.
        guard case .object(let json) = try JSONDecoder().decode(Internals.JSONValue.self, from: encoder.encode(mock))
        else {
            Issue.record("Expected the mock to encode as a JSON object")
            return
        }

        // When
        #expect(resolved.requestConfiguration.queries.isEmpty)

        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == [
                "application/x-www-form-urlencoded; charset=UTF-16"
            ]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == (data?.count).map { [String($0)] }
        )

        #expect(
            try Set(components)
                == Set(
                    json.reduce([]) {
                        try $0
                            + URLEncoder().encode($1.value.unwrapped, forKey: $1.key).map {
                                let query = $0
                                return "\(query.name)=\(query.value)"
                            }
                    }
                )
        )
    }

    @Test
    func payload_whenGETInitDataWithURLEncoded() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)

        // Then
        let resolved = try await resolve(
            TestProperty {
                RequestMethod(.get)

                Payload(
                    data: data,
                    contentType: .formURLEncoded
                )
            }
        )

        let resolvedData = try await resolved.requestConfiguration.body?.data()

        // When
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/x-www-form-urlencoded"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        #expect(resolvedData == data)

        #expect(resolved.requestConfiguration.url == "https://www.apple.com")
    }
}

// MARK: - Others tests

extension PayloadTests {

    @Test
    func payload_whenInitDataWithChunkSize() async throws {
        // Given
        let data = await Data.randomData(length: 1_024 * 1_024)
        let chunkSize = 1_024

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(data: data)
                    .payloadChunkSize(chunkSize)
            }
        )

        let buffers = try await resolved.requestConfiguration.body?.buffers() ?? []

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(
            resolved.requestConfiguration.headers["Content-Length"] == [String(data.count)]
        )

        let totalBytes = data.count
        let resolvedData = try await Array(buffers.async.compactMap { await $0.getData() })
        #expect(
            resolvedData
                == stride(from: .zero, to: data.count, by: chunkSize).map {
                    let upperBound = $0 + chunkSize
                    return data[$0..<(upperBound <= totalBytes ? upperBound : totalBytes)]
                }
        )
    }

    // `Payload(_:options:contentType:)` only exists on Darwin — same reason as the other
    // `Any`-based blocks in this file.
    #if canImport(Darwin)

    @Test
    func payload_whenInvalidJSONObject() async throws {
        // Given
        let jsonObject: Any = { () in }
        var encodingError: EncodingPayloadError?

        // When
        do {
            _ = try await resolve(
                TestProperty {
                    Payload(jsonObject)
                }
            )
        } catch let error as EncodingPayloadError {
            encodingError = error
        }

        // Then
        #expect(encodingError?.context == .invalidJSONObject)
    }

    #endif

    @Test
    func payload_whenEmptyPayload() async throws {
        // Given
        let data = Data()

        // When
        let resolved = try await resolve(
            TestProperty {
                Payload(data: data)
            }
        )

        let buffers = try await resolved.requestConfiguration.body?.buffers() ?? []

        // Then
        #expect(
            resolved.requestConfiguration.headers["Content-Type"] == ["application/octet-stream"]
        )

        #expect(resolved.requestConfiguration.headers["Content-Length"] == nil)

        let resolvedData = await buffers.resolveData()
        #expect(resolvedData.reduce(Data(), +) == data)
    }
}
