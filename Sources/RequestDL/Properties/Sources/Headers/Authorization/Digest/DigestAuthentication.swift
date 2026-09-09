//
// See LICENSE for this package's licensing information.
//

/// Sets the `Authorization` header for HTTP Digest access authentication (RFC 7616), once the
/// current ``DigestCredential`` has a challenge to answer.
///
/// Pairs with ``RequestTask/digestAuthentication(_:maxAttempts:)``, which parses the server's
/// `WWW-Authenticate: Digest` challenge on a `401`, stores it on a `DigestCredential`, and
/// retries -- this property alone only ever *uses* a challenge already stored there; it never
/// fetches one itself. The credential itself is never passed explicitly: it flows down through
/// the environment the same way ``URLEncoder`` does, from whichever
/// ``RequestTask/digestAuthentication(_:maxAttempts:)`` this request is under.
///
/// ```swift
/// try await DataTask {
///     BaseURL("example.com")
///     Path("secure")
///     DigestAuthentication(username: "user", password: "pass")
/// }
/// .digestAuthentication()
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

    @RequestEnvironment(\.digestCredential) private var credential: DigestCredential

    private let username: String
    private let password: String
    private let method: HTTPMethod

    // MARK: - Inits

    ///
    /// Initializes with the request's own username/password/method.
    ///
    /// - Parameters:
    ///    - username: The username to authenticate with.
    ///    - password: The password to authenticate with.
    ///    - method: The request's own HTTP method -- must match whatever ``RequestMethod`` (or
    ///    the default `GET`) this request actually uses, since it is hashed into the digest
    ///    response. Defaults to `.get`.
    ///
    public init(
        username: String,
        password: String,
        method: HTTPMethod = .get
    ) {
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

        // A leaf property with a hand-written `_makeProperty` doesn't go through `Property`'s
        // own default implementation, which is what runs `GraphOperation` (namespace,
        // environment, stored object) for every composite property automatically -- without
        // this, `@RequestEnvironment(\.digestCredential)` above would never see anything set via
        // `.environment(\.digestCredential, ...)`/`Modifiers.DigestAuthentication` and would
        // silently fall back to `DigestCredentialEnvironmentKey`'s own shared default.
        var inputs = inputs
        GraphOperation(property)(&inputs)

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
