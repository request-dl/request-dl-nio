/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class PayloadTests: XCTestCase {

    struct Mock: Codable, Equatable {
        let foo: String
        let date: Date
    }

    func testDictionaryPayload() async throws {
        // Given
        let dictionary: [String: Any] = [
            "foo": "bar",
            "number": 123
        ]

        let options = JSONSerialization.WritingOptions([.withoutEscapingSlashes])

        // When
        let property = TestProperty(Payload(dictionary, options: options))
        let (_, request) = try await resolve(property)
        let expectedPayload = _DictionaryPayload(dictionary, options: options)
        let payload = try await request.body?.data()

        let payloadDecoded = try payload.map {
            try JSONSerialization.jsonObject(with: $0)
        } as? [String: Any]

        let expectedPayloadDecoded = try JSONSerialization.jsonObject(
            with: expectedPayload.buffer.getData() ?? Data()
        ) as? [String: Any]

        // Then
        XCTAssertNotNil(payloadDecoded)
        XCTAssertEqual(
            payloadDecoded?.mapValues { "\($0)" },
            expectedPayloadDecoded?.mapValues { "\($0)" }
        )
    }

    func testStringPayload() async throws {
        // Given
        let foo = "foo"
        let encoding = String.Encoding.utf8

        // When
        let property = TestProperty(Payload(foo, using: encoding))
        let (_, request) = try await resolve(property)
        let expectedPayload = _StringPayload(foo, using: encoding)
        let payload = try await request.body?.data()

        // Then
        XCTAssertEqual(payload, expectedPayload.buffer.getData())
    }

    func testDataPayload() async throws {
        // Given
        let data = Data("foo,bar".utf8)

        // When
        let property = TestProperty(Payload(data))
        let (_, request) = try await resolve(property)
        let expectedPayload = _DataPayload(data)
        let payload = try await request.body?.data()

        // Then
        XCTAssertEqual(payload, expectedPayload.buffer.getData())
    }

    func testEncodablePayload() async throws {
        // Given
        let mock = Mock(
            foo: "foo",
            date: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        // When
        let property = TestProperty(Payload(mock, encoder: encoder))
        let (_, request) = try await resolve(property)
        let expectedPayload = _EncodablePayload(mock, encoder: encoder)

        let expectedData = expectedPayload.buffer.getData() ?? Data()
        let expectedMock = try decoder.decode(Mock.self, from: expectedData)
        let payloadMock = try await (request.body?.data()).map {
            try decoder.decode(Mock.self, from: $0)
        }

        // Then
        XCTAssertEqual(payloadMock, expectedMock)
        XCTAssertEqual(mock.foo, expectedMock.foo)

        XCTAssertEqual(
            mock.date.seconds,
            expectedMock.date.seconds
        )
    }

    func testFilePayload() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("file_payload")

        try url.createPathIfNeeded()
        defer { try? url.removeIfNeeded() }

        try data.write(to: url)

        // When
        let property = TestProperty(Payload(url))
        let (_, request) = try await resolve(property)
        let expectedPayload = _FilePayload(url)
        let payload = try await request.body?.data()

        // Then
        XCTAssertEqual(payload, expectedPayload.buffer.getData())
    }

    func testPayload_whenGETEncodableURLEncoded() async throws {
        // Given
        let array = ["foo", "bar"]

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.ContentType(.formURLEncoded)
            RequestMethod(.get)
            Payload(array)
        })

        let sut = request.queries
            .joined()
            .split(separator: "&")

        // Then
        XCTAssertEqual(sut.sorted(), [
            "0=foo",
            "1=bar"
        ])
    }

    func testPayload_whenHEADEncodableURLEncoded() async throws {
        // Given
        let array = ["foo", "bar"]

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.ContentType(.formURLEncoded)
            RequestMethod(.head)
            Payload(array)
        })

        let sut = request.queries
            .joined()
            .split(separator: "&")

        // Then
        XCTAssertEqual(sut.sorted(), [
            "0=foo",
            "1=bar"
        ])
    }

    func testPayload_whenPOSTEncodableURLEncoded() async throws {
        // Given
        let array = ["foo", "bar"]

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.ContentType(.formURLEncoded)
            RequestMethod(.post)
            Payload(array)
        })

        let sut = try await (request.body?.data())
            .flatMap { String(data: $0, encoding: .utf8) }?
            .split(separator: "&")

        // Then
        XCTAssertEqual(sut?.sorted(), [
            "0=foo",
            "1=bar"
        ])
    }

    func testPayload_whenGETDictionaryURLEncoded() async throws {
        // Given
        let dictionary = [
            "foo": "bar",
            "key": "value"
        ]

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.ContentType(.formURLEncoded)
            RequestMethod(.get)
            Payload(dictionary)
        })

        let sut = request.queries
            .joined()
            .split(separator: "&")

        // Then
        XCTAssertEqual(sut.sorted(), [
            "foo=bar",
            "key=value"
        ])
    }

    func testPayload_whenPOSTDictionaryURLEncoded() async throws {
        // Given
        let dictionary = [
            "foo": "bar",
            "key": "value"
        ]

        // When
        let (_, request) = try await resolve(TestProperty {
            Headers.ContentType(.formURLEncoded)
            RequestMethod(.post)
            Payload(dictionary)
        })

        let sut = try await (request.body?.data())
            .flatMap { String(data: $0, encoding: .utf8) }?
            .split(separator: "&")

        // Then
        XCTAssertEqual(sut?.sorted(), [
            "foo=bar",
            "key=value"
        ])
    }

    func testNeverBody() async throws {
        // Given
        let property = Payload(Data())

        // Then
        try await assertNever(property.body)
    }

    func testPayload_whenPartLengthSet() async throws {
        // Given
        let length = 2

        // When
        let (_, request) = try await resolve(TestProperty {
            Payload("abc", using: .utf8)
                .payloadPartLength(length)
        })

        let sut = try await request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 2)
    }
}
