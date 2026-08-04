//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import class Foundation.JSONDecoder
#endif

extension Internals {
    /// A decoded JSON tree.
    ///
    /// Exists so an `Encodable` can be turned into form fields without `JSONSerialization`, which
    /// is not part of `FoundationEssentials`. `JSONDecoder` is, so the round trip goes
    /// `Encodable -> Data -> JSONValue` instead of `Encodable -> Data -> Any`.
    ///
    /// ## Why the number cases are split
    ///
    /// `JSONSerialization` hands back `NSNumber`, which prints `1` for an integer and `1.5` for a
    /// fractional one. Decoding everything as `Double` would have turned every integer field into
    /// `1.0` on the wire, so the integer forms are tried first and kept as such.
    enum JSONValue: Sendable, Codable {

        case null
        case bool(Bool)
        case integer(Int64)
        case unsignedInteger(UInt64)
        case double(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        // MARK: - Internal properties

        /// This tree as the loosely typed values ``URLEncoder`` walks.
        ///
        /// - Note: `null` becomes a Swift `Optional`, not a null marker, so it reaches
        /// ``URLEncoder/OptionalEncodingStrategy`` like any other empty value. Under
        /// `JSONSerialization` it arrived as `NSNull`, matched no case in the encoder's switch and
        /// fell through to string interpolation, which put the literal `<null>` in the query. The
        /// configured strategy now applies instead, so the default emits `nil`.
        var rawValue: Any {
            switch self {
            case .null:
                // A typed `Optional`, because the encoder recognises `nil` by casting the dynamic
                // type to its `OptionalLiteral` protocol.
                return String?.none as Any
            case .bool(let value):
                return value
            case .integer(let value):
                return value
            case .unsignedInteger(let value):
                return value
            case .double(let value):
                return value
            case .string(let value):
                return value
            case .array(let values):
                return values.map(\.rawValue)
            case .object(let values):
                return values.mapValues(\.rawValue)
            }
        }

        // MARK: - Inits

        init(from decoder: any Decoder) throws {
            // Containers are tried widest first. A keyed container over an array or a scalar
            // throws, so `try?` is the type test here.
            if let container = try? decoder.container(keyedBy: ObjectKey.self) {
                var object = [String: JSONValue](minimumCapacity: container.allKeys.count)

                for key in container.allKeys {
                    object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                }

                self = .object(object)
                return
            }

            if var container = try? decoder.unkeyedContainer() {
                var array = [JSONValue]()

                if let count = container.count {
                    array.reserveCapacity(count)
                }

                while !container.isAtEnd {
                    array.append(try container.decode(JSONValue.self))
                }

                self = .array(array)
                return
            }

            let container = try decoder.singleValueContainer()

            if container.decodeNil() {
                self = .null
                return
            }

            // Order matters. `Bool` first, because a decoder that coerces would otherwise read
            // `true` as a number; the integer forms before `Double`, to keep `1` from becoming
            // `1.0`; and `Int64` before `UInt64`, so a negative value is not rejected.
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(UInt64.self) {
                self = .unsignedInteger(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Value is not a JSON null, boolean, number or string"
                )
            }
        }

        // MARK: - Internal static methods

        /// Decodes `data`, or `nil` when it is not a JSON tree this can represent.
        ///
        /// - Note: Returns rather than throwing. The only caller has a fallback that sends the
        /// bytes as they are, which is what a top level fragment should do, and it is also what
        /// the `JSONSerialization` version did through its `default` branch.
        static func decoding(_ data: Data) -> JSONValue? {
            try? JSONDecoder().decode(JSONValue.self, from: data)
        }

        // MARK: - Internal methods

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .null:
                try container.encodeNil()
            case .bool(let value):
                try container.encode(value)
            case .integer(let value):
                try container.encode(value)
            case .unsignedInteger(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .object(let value):
                try container.encode(value)
            }
        }
    }

    // MARK: - ObjectKey

    /// A coding key for arbitrary JSON object names.
    private struct ObjectKey: CodingKey {

        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

}
