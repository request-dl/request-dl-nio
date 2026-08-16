//
// See LICENSE for this package's licensing information.
//

@testable import RequestDL

extension Internals.JSONValue {

    /// Unwraps to whichever native Swift value callers that predate this type already know how
    /// to work with — the shape `URLEncoder.encode(_:forKey:)` accepts.
    var unwrapped: Any {
        switch self {
        case .null:
            return Optional<Any>.none as Any
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
        case .array(let value):
            return value.map(\.unwrapped)
        case .object(let value):
            return value.mapValues(\.unwrapped)
        }
    }
}
