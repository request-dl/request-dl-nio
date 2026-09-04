//
// See LICENSE for this package's licensing information.
//

/// Sets the `Authorization` header for HTTP Digest access authentication (RFC 7616), once its
/// `credential` has a challenge to answer.
///
/// Pairs with ``RequestTask/digestAuthentication(_:maxAttempts:)``, which parses the server's
/// `WWW-Authenticate: Digest` challenge on a `401` and retries -- this property alone only ever
/// *uses* a challenge already stored on `credential`; it never fetches one itself. See
/// ``DigestCredential``'s own doc comment for the shared-state contract between the two.
///
/// ```swift
/// let credential = DigestCredential()
///
/// try await DataTask {
///     BaseURL("example.com")
///     Path("secure")
///     DigestAuthentication(credential, username: "user", password: "pass")
/// }
/// .digestAuthentication(credential)
/// .result()
/// ```
///
/// - Important: Place this *after* every property that contributes to the URL (``BaseURL``,
/// ``Path``, ``Query``) or the method (``RequestMethod``) -- the digest response is computed over
/// whatever they have already set by the time this runs, same as every other property that reads
/// `Make` rather than only writing to it.
///
/// - Note: Only `qop=auth` (or no `qop` at all, RFC 2069 style) is supported -- `qop=auth-int`,
/// which additionally hashes the request body, is not. Neither are the `-sess` algorithm variants
/// (`MD5-sess`/`SHA-256-sess`). A challenge asking for either is treated as unusable, the same as
/// one missing `realm`/`nonce` entirely: this property contributes no header, and the request
/// goes out exactly as it would have without ``DigestAuthentication`` at all.
public struct DigestAuthentication: Property {

    private struct Node: PropertyNode {

        let credential: DigestCredential
        let username: String
        let password: String
        let method: String

        func make(_ make: inout Make) async throws {
            guard let challenge = credential.challenge else {
                return
            }

            let path = make.requestConfiguration.pathComponents.joinedAsPath()
            let query = make.requestConfiguration.queries.joined()
            let uri = query.isEmpty ? "/\(path)" : "/\(path)?\(query)"

            let header = DigestResponse.header(
                for: challenge,
                username: username,
                password: password,
                method: method,
                uri: uri
            )

            make.requestConfiguration.headers.set(
                name: "Authorization",
                value: header
            )
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let credential: DigestCredential
    private let username: String
    private let password: String
    private let method: HTTPMethod

    // MARK: - Inits

    ///
    /// Initializes with the shared credential and the request's own username/password/method.
    ///
    /// - Parameters:
    ///    - credential: Shared with ``RequestTask/digestAuthentication(_:maxAttempts:)``. See
    ///    ``DigestCredential``.
    ///    - username: The username to authenticate with.
    ///    - password: The password to authenticate with.
    ///    - method: The request's own HTTP method -- must match whatever ``RequestMethod`` (or
    ///    the default `GET`) this request actually uses, since it is hashed into the digest
    ///    response. Defaults to `.get`.
    ///
    public init(
        _ credential: DigestCredential,
        username: String,
        password: String,
        method: HTTPMethod = .get
    ) {
        self.credential = credential
        self.username = username
        self.password = password
        self.method = method
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<DigestAuthentication>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                credential: property.credential,
                username: property.username,
                password: property.password,
                method: property.method.rawValue
            )
        )
    }
}
