//
// See LICENSE for this package's licensing information.
//

import Foundation

extension Internals.Cookie {

    /// Where a `Set-Cookie` header came from: the request whose response carried it.
    package struct Origin: Sendable, Equatable {

        /// Lowercased host of the request URL.
        package let host: String
        package let path: String

        /// Whether the connection the response arrived on was TLS, or to a loopback host.
        package let isSecure: Bool

        package init(host: String, path: String, isSecure: Bool) {
            self.host = host
            self.path = path
            self.isSecure = isSecure
        }
    }

    /// Parses one `Set-Cookie` header value received from `origin`, or returns `nil` when RFC 6265
    /// says to ignore it, or when it is one the storage must not accept (see below).
    ///
    /// Beyond RFC 6265 section 5.2 it rejects the cookies that would otherwise let one hostile
    /// server break every later request or reach other sites:
    ///
    /// - a name or a value with a control character, which `HeaderValidation` would later refuse
    ///   to send, failing every request to the host;
    /// - a name and a value larger than 4096 bytes;
    /// - a `Secure` cookie from an insecure origin;
    /// - `__Secure-` and `__Host-` cookies that do not meet their prefix's rules;
    /// - a `Domain` that is a public suffix (per `publicSuffixList`), or a single label.
    package static func parse(
        _ header: String,
        from origin: Origin,
        now: Date,
        publicSuffixList: Internals.PublicSuffixList?
    ) -> Internals.Cookie? {
        let components = header.split(separator: ";", omittingEmptySubsequences: false)

        guard let pair = components.first, let equals = pair.firstIndex(of: "=") else {
            return nil
        }

        let name = trimmed(pair[..<equals])
        let value = trimmed(pair[pair.index(after: equals)...])

        guard nameValueRejection(name: name, value: value) == nil else {
            return nil
        }

        var domain: String?
        var path: String?
        var secure = false
        var httpOnly = false
        var maxAge: Int?
        var expires: Date?

        for attribute in components.dropFirst() {
            let (rawName, rawValue) = split(attribute)
            let attributeName = rawName.lowercased()

            guard rawValue.utf8.count <= maximumAttributeValueLength else {
                continue
            }

            switch attributeName {
            case "domain":
                let cleaned = rawValue.hasPrefix(".") ? String(rawValue.dropFirst()) : rawValue
                // An empty `Domain` is ignored, as RFC 6265bis says: it does not undo an earlier one.
                if !cleaned.isEmpty {
                    domain = Internals.HostName.ascii(cleaned)
                }
            case "path":
                path = rawValue.hasPrefix("/") ? rawValue : nil
            case "secure":
                secure = true
            case "httponly":
                httpOnly = true
            case "max-age":
                maxAge = parseMaxAge(rawValue) ?? maxAge
            case "expires":
                expires = parseDate(rawValue) ?? expires
            default:
                break
            }
        }

        guard !secure || origin.isSecure else {
            return nil
        }

        guard
            let (cookieDomain, hostOnly) = resolveDomain(
                attribute: domain,
                origin: origin,
                publicSuffixList: publicSuffixList
            )
        else {
            return nil
        }

        let cookiePath = path ?? defaultPath(of: origin.path)

        guard
            satisfiesPrefixRules(
                name: name,
                secure: secure,
                hasDomainAttribute: !hostOnly,
                path: cookiePath
            )
        else {
            return nil
        }

        // Max-Age wins over Expires, and is relative to now: the instant it was received.
        let expiry: Date?
        if let maxAge {
            expiry = maxAge <= 0 ? .distantPast : now.addingTimeInterval(TimeInterval(maxAge))
        } else {
            expiry = expires
        }

        return Internals.Cookie(
            name: name,
            value: value,
            domain: cookieDomain,
            hostOnly: hostOnly,
            path: cookiePath,
            secure: secure,
            httpOnly: httpOnly,
            expires: expiry,
            creation: now
        )
    }

    // MARK: - Private static methods

    /// RFC 6265 section 5.3, steps 5 and 6, plus the supercookie guard.
    private static func resolveDomain(
        attribute: String?,
        origin: Origin,
        publicSuffixList: Internals.PublicSuffixList?
    ) -> (domain: String, hostOnly: Bool)? {
        guard let attribute else {
            return (origin.host, true)
        }

        // A Domain attribute never applies to an IP address, except the one it names itself.
        if isIPAddress(origin.host) || isIPAddress(attribute) {
            return attribute == origin.host ? (origin.host, true) : nil
        }

        // A single label is never allowed, with a list or without one: the Public Suffix List's own
        // algorithm treats an unlisted label as a suffix (its implicit `*` rule), and a list that
        // is out of date, or has a TLD only as a wildcard, would otherwise let `Domain=corp`, or
        // `Domain=ck`, through. A list adds the multi-label suffixes (`co.uk`) to that.
        if isPublicSuffixOrSingleLabel(attribute, publicSuffixList: publicSuffixList) {
            // `Domain=localhost` from localhost itself is the one harmless case.
            return attribute == origin.host ? (origin.host, true) : nil
        }

        guard domainMatches(host: origin.host, domain: attribute) else {
            return nil
        }

        return (attribute, false)
    }

    /// RFC 6265bis section 4.1.3.
    static func satisfiesPrefixRules(
        name: String,
        secure: Bool,
        hasDomainAttribute: Bool,
        path: String
    ) -> Bool {
        let lowercased = name.lowercased()

        if lowercased.hasPrefix("__secure-") {
            return secure
        }

        if lowercased.hasPrefix("__host-") {
            return secure && !hasDomainAttribute && path == "/"
        }

        return true
    }

    private static func trimmed(_ substring: Substring) -> String {
        String(substring.drop { $0 == " " || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
    }

    private static func split(_ attribute: Substring) -> (name: String, value: String) {
        guard let equals = attribute.firstIndex(of: "=") else {
            return (trimmed(attribute), "")
        }

        return (trimmed(attribute[..<equals]), trimmed(attribute[attribute.index(after: equals)...]))
    }

    /// `[-] 1*DIGIT`, per section 5.2.2: a leading `+` is not allowed, even though `Int` takes it.
    private static func parseMaxAge(_ string: String) -> Int? {
        let digits = string.hasPrefix("-") ? string.dropFirst() : Substring(string)

        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }

        // A value too large for Int is an expiry far in the future (or past), not an error.
        guard let value = Int(string) else {
            return string.hasPrefix("-") ? Int.min / 2 : Int.max / 2
        }

        return value
    }
}
