//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension CookieJar {

    /// A cookie held by a ``CookieJar``.
    ///
    /// A plain value: reading one out of a jar gives a copy, and changing it changes nothing in the
    /// jar until you ``CookieJar/insert(_:)`` it back. Building one by hand does not check it; the jar
    /// does, when you insert it, with the rules it applies to the cookies its responses set (see
    /// ``CookieJar/insert(_:)`` for where they differ).
    ///
    /// - Important: `value` is a credential. A cookie describes itself, and the snapshot that holds
    ///   it describes itself, without it (`<redacted>`), so a stray `print` or a log line does not
    ///   leak a session. Encoding a cookie writes the value, because that is what encoding is for:
    ///   see <doc:Using-Cookies> before keeping the result anywhere.
    public struct Cookie: Sendable, Hashable, Codable {

        // MARK: - Public properties

        /// The name of the cookie. Not empty, ASCII only, and without `;`, `=` or control characters.
        public var name: String

        /// The value of the cookie, sent back as it is. ASCII only (RFC 6265), and without `;` or control
        /// characters.
        public var value: String

        /// The domain the cookie belongs to: lowercase, in Punycode, without a leading dot. The jar
        /// normalizes it that way when you insert the cookie, and a cookie read from the jar has it so.
        public var domain: String

        /// `true` when only `domain` itself is sent the cookie, as when the server sets no `Domain`
        /// attribute. `false` when its subdomains are too.
        public var hostOnly: Bool

        /// The path the cookie applies to, below which it is sent. Starts with `/`.
        public var path: String

        /// Whether the cookie is sent over HTTPS only (and to loopback addresses).
        public var secure: Bool

        /// The `HttpOnly` attribute. It hides the cookie from scripts in a browser; a jar sends an
        /// `HttpOnly` cookie like any other, and gives it to the code that asks it.
        public var httpOnly: Bool

        /// When the cookie expires, or `nil` for a session cookie, which the jar keeps until it is
        /// cleared. A `Max-Age` the server sent is already resolved to this instant.
        public var expires: Date?

        /// When the jar first stored the cookie. A cookie that replaces another keeps the creation
        /// of the one it replaced (RFC 6265, section 5.3), so it is not a "last modified".
        public let creation: Date

        // MARK: - Inits

        /// Creates a cookie.
        ///
        /// - Parameters:
        ///   - name: The name of the cookie.
        ///   - value: The value of the cookie.
        ///   - domain: The host the cookie is for, or the domain whose subdomains it is for when
        ///     `hostOnly` is `false`.
        ///   - hostOnly: Whether only `domain` itself is sent the cookie.
        ///   - path: Where the cookie applies.
        ///   - secure: Whether it is sent over HTTPS only.
        ///   - httpOnly: The `HttpOnly` attribute.
        ///   - expires: When it expires, or `nil` for a session cookie.
        ///   - creation: When it was created.
        public init(
            name: String,
            value: String,
            domain: String,
            hostOnly: Bool = true,
            path: String = "/",
            secure: Bool = false,
            httpOnly: Bool = false,
            expires: Date? = nil,
            creation: Date = Date()
        ) {
            self.name = name
            self.value = value
            self.domain = domain
            self.hostOnly = hostOnly
            self.path = path
            self.secure = secure
            self.httpOnly = httpOnly
            self.expires = expires
            self.creation = creation
        }

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            case name
            case value
            case domain
            case hostOnly
            case path
            case secure
            case httpOnly
            case expires
            case creation
        }

        /// Dates are decoded from, and encoded as, the number of seconds since 1970, whatever the
        /// decoder's or encoder's date strategy: a snapshot written by one must read back the same
        /// with another.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(String.self, forKey: .value)
            domain = try container.decode(String.self, forKey: .domain)
            hostOnly = try container.decode(Bool.self, forKey: .hostOnly)
            path = try container.decode(String.self, forKey: .path)
            secure = try container.decode(Bool.self, forKey: .secure)
            httpOnly = try container.decode(Bool.self, forKey: .httpOnly)
            expires = try container.decodeIfPresent(Double.self, forKey: .expires).map(
                Date.init(timeIntervalSince1970:)
            )
            creation = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .creation))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(name, forKey: .name)
            try container.encode(value, forKey: .value)
            try container.encode(domain, forKey: .domain)
            try container.encode(hostOnly, forKey: .hostOnly)
            try container.encode(path, forKey: .path)
            try container.encode(secure, forKey: .secure)
            try container.encode(httpOnly, forKey: .httpOnly)
            try container.encodeIfPresent(expires?.timeIntervalSince1970, forKey: .expires)
            try container.encode(creation.timeIntervalSince1970, forKey: .creation)
        }
    }
}

// MARK: - Describing

extension CookieJar.Cookie: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    /// The cookie without its value.
    public var description: String {
        var flags = [String]()

        if hostOnly {
            flags.append("hostOnly")
        }

        if secure {
            flags.append("secure")
        }

        if httpOnly {
            flags.append("httpOnly")
        }

        if expires == nil {
            flags.append("session")
        }

        let suffix = flags.isEmpty ? "" : ", " + flags.joined(separator: ", ")
        return "Cookie(\(name), \(domain), \(path)\(suffix), value: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "name": name,
                "value": "<redacted>",
                "domain": domain,
                "hostOnly": hostOnly,
                "path": path,
                "secure": secure,
                "httpOnly": httpOnly,
                "expires": expires as Any,
                "creation": creation,
            ],
            displayStyle: .struct
        )
    }
}

// MARK: - Internals

extension CookieJar.Cookie {

    init(_ cookie: Internals.Cookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            hostOnly: cookie.hostOnly,
            path: cookie.path,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            expires: cookie.expires,
            creation: cookie.creation
        )
    }

    var internalCookie: Internals.Cookie {
        Internals.Cookie(
            name: name,
            value: value,
            domain: domain,
            hostOnly: hostOnly,
            path: path,
            secure: secure,
            httpOnly: httpOnly,
            expires: expires,
            creation: creation
        )
    }
}
