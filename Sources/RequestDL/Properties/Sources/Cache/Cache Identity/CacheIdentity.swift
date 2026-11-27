//
// See LICENSE for this package's licensing information.
//

///
/// Declares which account a request is made for, so that the cache tells accounts apart by that
/// instead of by the credentials the request sends.
///
/// A response stored for a request that sends `Authorization`, `Cookie` or `Proxy-Authorization`
/// is only served to a request that sends the same. That is right for a token that does not
/// change, and wrong for one that does: an OAuth token that is refreshed, or a session cookie the
/// server re-issues on every response, is a new credential for the same account, and the cache
/// never hits across the refresh. Declaring the account puts that decision with the app, which
/// knows it:
///
/// ```swift
/// DataTask {
///     BaseURL("https://api.example.com")
///     Path("/me/orders")
///     Authorization(.bearer, token: session.accessToken)
///     CacheIdentity(session.userID)
/// }
/// .cachePolicy(.all)
/// ```
///
/// With a `CacheIdentity` on the request:
///
/// - The response is stored for that identity and for no other, and the credentials the request
///   sent are not looked at: a request with the same identity is served it whatever
///   `Authorization` or `Cookie` it carries. The identity is not stored as written but as a
///   digest. With an ``DataCache/EncryptionKey`` on the cache it is an HMAC-SHA256 under a key
///   derived from it, which cannot be computed, or checked against a guess, without the key.
///   Without one it is a plain SHA-256 and **is not a secret**: it hides nothing that can be
///   guessed (a numeric user ID, an email address), and whoever can read the cache directory can
///   test candidates against it. Declare an opaque identifier (a random account ID that means
///   nothing outside the app) or set an encryption key.
/// - A response whose `Vary` lists `Authorization`, `Cookie` or `Proxy-Authorization` is still
///   served to the same identity: the identity stands in for those fields. Any other field in
///   `Vary` is compared as usual.
/// - It is not served to a request with another identity, nor to one with none. A response stored
///   for a request with an identity is only given to a request that declares it.
/// - A response stored for a request with no credentials and no identity (a public one) is
///   served to every request, as it always was. A response stored for a request that sent
///   credentials but declared no identity is not served to a request that declares one.
///
/// The identity is a claim that the app makes: the cache does not check that the credentials the
/// request sends belong to it. Two accounts that are given the same identity share what they
/// cache.
///
/// An identity that is empty, or only whitespace, is ignored, as if the property were not there:
/// the request is cached by its credentials, which is the safe choice, since an account whose ID
/// is not known yet cannot be mistaken for another that way. The last `CacheIdentity` of a
/// request wins. It is not part of the cache key, which stays the URL, and nothing is sent to the
/// server.
///
/// > Note: Only a request that uses the cache looks at the identity. A response fetched through
/// a redirect on which the cookie jar sent cookies that the request did not carry is still not
/// stored.
///
public struct CacheIdentity: Property {

    private struct Node: PropertyNode {

        let identity: String

        func make(_ make: inout Make) async throws {
            make.requestConfiguration.cacheIdentity = identity
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let identity: String

    // MARK: - Inits

    ///
    /// Creates a cache identity.
    ///
    /// - Parameter identity: What tells the account apart from the others, such as a user ID. It
    /// is compared exactly (case and inner whitespace count); leading and trailing whitespace is
    /// ignored, and an identity that is empty after that is ignored altogether.
    ///
    public init(_ identity: String) {
        self.identity = identity
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<CacheIdentity>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(identity: property.identity))
    }
}
