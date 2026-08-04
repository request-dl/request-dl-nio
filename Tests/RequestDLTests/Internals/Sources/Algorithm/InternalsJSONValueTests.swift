//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import class Foundation.JSONDecoder
// import class Foundation.JSONEncoder
#endif

struct InternalsJSONValueTests {

    // MARK: - rawValue

    @Test
    func rawValueUnwrapsEveryCase() {
        #expect(Internals.JSONValue.null.rawValue is String?)
        #expect(Internals.JSONValue.bool(true).rawValue as? Bool == true)
        #expect(Internals.JSONValue.integer(42).rawValue as? Int64 == 42)
        #expect(Internals.JSONValue.unsignedInteger(42).rawValue as? UInt64 == 42)
        #expect(Internals.JSONValue.double(1.5).rawValue as? Double == 1.5)
        #expect(Internals.JSONValue.string("hi").rawValue as? String == "hi")
        #expect((Internals.JSONValue.array([.integer(1)]).rawValue as? [Any])?.count == 1)
        #expect((Internals.JSONValue.object(["a": .integer(1)]).rawValue as? [String: Any])?.count == 1)
    }

    // MARK: - init(from:) scalar branches

    @Test
    func decodingNullYieldsTheNullCase() throws {
        let value = try JSONDecoder().decode(Internals.JSONValue.self, from: Data("null".utf8))

        guard case .null = value else {
            Issue.record("Expected .null, got \(value)")
            return
        }
    }

    @Test
    func decodingBoolYieldsTheBoolCase() throws {
        let value = try JSONDecoder().decode(Internals.JSONValue.self, from: Data("true".utf8))

        guard case .bool(let bool) = value else {
            Issue.record("Expected .bool, got \(value)")
            return
        }

        #expect(bool)
    }

    @Test
    func decodingAValueTooLargeForInt64YieldsTheUnsignedIntegerCase() throws {
        // Given
        // `UInt64.max` overflows `Int64`, so the `Int64` decode attempt has to fail first for
        // the `UInt64` branch to run.
        let data = Data(String(UInt64.max).utf8)

        // When
        let value = try JSONDecoder().decode(Internals.JSONValue.self, from: data)

        // Then
        guard case .unsignedInteger(let unsigned) = value else {
            Issue.record("Expected .unsignedInteger, got \(value)")
            return
        }

        #expect(unsigned == .max)
    }

    @Test
    func decodingAFractionalNumberYieldsTheDoubleCase() throws {
        let value = try JSONDecoder().decode(Internals.JSONValue.self, from: Data("1.5".utf8))

        guard case .double(let double) = value else {
            Issue.record("Expected .double, got \(value)")
            return
        }

        #expect(double == 1.5)
    }

    // MARK: - decoding(_:)

    @Test
    func decodingInvalidJSONReturnsNil() {
        #expect(Internals.JSONValue.decoding(Data("not json".utf8)) == nil)
    }

    @Test
    func decodingValidJSONRoundTrips() {
        let decoded = Internals.JSONValue.decoding(Data(#"{"a":1}"#.utf8))

        guard case .object(let object) = decoded else {
            Issue.record("Expected .object, got \(String(describing: decoded))")
            return
        }

        guard case .integer(let value) = object["a"] else {
            Issue.record("Expected key \"a\" to be .integer, got \(String(describing: object["a"]))")
            return
        }

        #expect(value == 1)
    }

    // MARK: - encode(to:)

    @Test
    func encodingEveryCaseProducesTheExpectedJSON() throws {
        let cases: [(Internals.JSONValue, String)] = [
            (.null, "null"),
            (.bool(true), "true"),
            (.integer(-1), "-1"),
            (.unsignedInteger(.max), String(UInt64.max)),
            (.double(1.5), "1.5"),
            (.string("hi"), "\"hi\""),
        ]

        for (value, expectedJSON) in cases {
            let data = try JSONEncoder().encode(value)
            #expect(String(decoding: data, as: UTF8.self) == expectedJSON)
        }

        // `.array`/`.object` don't have a single canonical serialization (element/key order),
        // so round-trip them through decode instead of comparing raw JSON text.
        let arrayData = try JSONEncoder().encode(Internals.JSONValue.array([.integer(1), .string("two")]))
        let decodedArray = try JSONDecoder().decode(Internals.JSONValue.self, from: arrayData)
        guard case .array(let array) = decodedArray, array.count == 2 else {
            Issue.record("Expected a 2-element .array, got \(decodedArray)")
            return
        }

        let objectData = try JSONEncoder().encode(Internals.JSONValue.object(["key": .bool(false)]))
        let decodedObject = try JSONDecoder().decode(Internals.JSONValue.self, from: objectData)
        guard case .object(let object) = decodedObject, case .bool(let flag) = object["key"] else {
            Issue.record("Expected {\"key\": false}, got \(decodedObject)")
            return
        }
        #expect(flag == false)
    }
}
