//
// See LICENSE for this package's licensing information.
//

/// The `BaseURL` is the entry point as it specifies the scheme and host to be queried during the request.
///
/// ## Overview
///
/// To start using it, it is important to pay attention to some rules:
///
/// - Scheme must be of type ``RequestDL/URLScheme``.
/// - Host is a string without scheme.
///
/// ```swift
/// // Always HTTPS
/// BaseURL("apple.com")
///
/// // Specifying the scheme
/// BaseURL(.http, host: "apple.com")
/// ```
///
/// > Note: Successively specifying the `BaseURL` within a declarative block will override the previously specified value.
///
/// > Warning: It is extremely important to specify the BaseURL in each request. Otherwise, RequestDL may throw an error.
///
/// ### Learn the fundamentals
///
/// @Links(visualStyle: list) {
///     - <doc:Creating-requests-from-scratch>
///     - <doc:Cache-support>
/// }
public struct BaseURL: Property {

    private struct Node: PropertyNode {

        let scheme: URLScheme
        let host: String

        func make(_ make: inout Make) async throws {
            if host.contains("://") {
                throw BaseURLError(
                    context: .invalidHost,
                    baseURL: host
                )
            }

            // `host.split(separator: "/").first` used to stand in for this check: it silently
            // resolved to the leading component (`"apple.com/api/v1"` → `"apple.com"`, the path
            // dropped with no error) for any host containing a path, and only failed the way
            // `.unexpectedHost` is meant to for a host that is empty or all slashes. A host with
            // an accidental path in it — plausible input, e.g. copy-pasting a full URL's path
            // into `BaseURL` instead of using `Path` — deserves the same rejection `Path` belongs
            // in for, not silent truncation to a different request than the one written.
            guard !host.isEmpty, !host.contains("/") else {
                throw BaseURLError(
                    context: .unexpectedHost,
                    baseURL: host
                )
            }

            make.requestConfiguration.baseURL = "\(scheme.rawValue)://\(host)"
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let scheme: URLScheme
    let host: String

    // MARK: - Init

    ///
    /// Creates a BaseURL by combining the url scheme and the string host.
    ///
    /// ```swift
    /// import RequestDL
    ///
    /// struct AppleDeveloperBaseURL: Property {
    ///
    ///     var body: some Property {
    ///         BaseURL(.https, host: "developer.apple.com")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///    - scheme: The url scheme chosen.
    ///    - host: The string host only.
    ///
    public init(_ scheme: URLScheme, host: String) {
        self.scheme = scheme
        self.host = host
    }

    ///
    /// Defines the base URL from the host with the default HTTPS scheme.
    ///
    /// ```swift
    /// import RequestDL
    ///
    /// struct AppleDeveloperBaseURL: Property {
    ///
    ///     var body: some Property {
    ///         BaseURL("developer.apple.com")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///    - host: The string host only.
    ///
    public init(_ host: String) {
        self.init(.https, host: host)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<BaseURL>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                scheme: property.scheme,
                host: property.host
            )
        )
    }
}
