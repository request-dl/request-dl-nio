import Foundation

public enum StatusCodeValidation: Equatable {

    /// No validation.
    case none

    /// Validate success codes (only 2xx).
    case success

    /// Validate success codes and redirection codes (only 2xx and 3xx).
    case successAndRedirect

    /// Validate only the given status codes.
    case custom([Int])

    /// The list of HTTP status codes to validate.
    public var statusCodes: [Int] {
        switch self {
        case .success:
            return Array(200..<300)
        case .successAndRedirect:
            return Array(200..<400)
        case .custom(let codes):
            return codes
        case .none:
            return []
        }
    }

    public func validate(statusCode: Int) -> Bool {
        self == .none || statusCodes.contains(statusCode)
    }
}
