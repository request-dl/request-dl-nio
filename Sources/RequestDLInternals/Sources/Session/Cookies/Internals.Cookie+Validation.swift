//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.Cookie {

    /// Why a cookie was refused. Carries no payload: a cookie's value must never reach a log or a
    /// description through the reason it was refused.
    package enum Rejection: Error, Sendable, Equatable, CaseIterable {

        /// Empty, with a control character, a `;` or a `=`, or with a blank at either end.
        case invalidName

        /// With a control character, a `;`, or a blank at either end.
        case invalidValue

        /// Empty, not a host name or an IP literal, or an IP literal for a cookie that is not
        /// host-only.
        case invalidDomain

        /// Not starting with `/`, or with a control character or a `;`.
        case invalidPath

        /// A name and a value over 4096 bytes, or a domain or a path over 1024.
        case tooLarge

        /// A cookie that is not host-only for a single label or a public suffix.
        case publicSuffix

        /// A `__Secure-` or `__Host-` cookie that does not meet its prefix's rules.
        case prefixRule
    }

    /// Checks `cookie` as if it had no origin, the way a cookie that did not come from a response
    /// is: the one the caller of `CookieStorage.insert` or `restore` hands over.
    ///
    /// It is the same rules `parse` applies to a received cookie (control characters, sizes, prefix
    /// rules, public suffixes), and the ones that the grammar of a `Set-Cookie` header enforced
    /// without a check (`;` and `=` cannot be part of a name, `;` cannot be part of a value, and
    /// blanks around either are trimmed), which a cookie built by hand must be held to: a value of
    /// `x; admin=1` would otherwise put a second pair in the `Cookie` header.
    ///
    /// What it leaves out is what needs an origin, see `CookieStorage.insert`.
    ///
    /// - Parameter cookie: Expected to have its domain normalized (see ``normalizedDomain(_:)``).
    package static func rejection(
        of cookie: Internals.Cookie,
        publicSuffixList: Internals.PublicSuffixList?
    ) -> Rejection? {
        if let rejection = nameValueRejection(name: cookie.name, value: cookie.value) {
            return rejection
        }

        if let rejection = domainRejection(
            cookie.domain,
            hostOnly: cookie.hostOnly,
            publicSuffixList: publicSuffixList
        ) {
            return rejection
        }

        if let rejection = pathRejection(cookie.path) {
            return rejection
        }

        guard
            satisfiesPrefixRules(
                name: cookie.name,
                secure: cookie.secure,
                hasDomainAttribute: !cookie.hostOnly,
                path: cookie.path
            )
        else {
            return .prefixRule
        }

        return nil
    }

    /// `domain` the way the storage keeps it: lowercase, Punycode, without a leading dot or the
    /// brackets of an IPv6 literal.
    package static func normalizedDomain(_ domain: String) -> String {
        var domain = Internals.HostName.ascii(domain)

        if domain.hasPrefix(".") {
            domain.removeFirst()
        }

        if domain.hasPrefix("["), domain.hasSuffix("]") {
            domain = String(domain.dropFirst().dropLast())
        }

        return domain
    }

    // MARK: - Shared with `parse`

    static func nameValueRejection(name: String, value: String) -> Rejection? {
        guard
            !name.isEmpty,
            !hasControlCharacters(name),
            !name.contains(";"),
            !name.contains("="),
            !hasBlankEdge(name)
        else {
            return .invalidName
        }

        guard
            !hasControlCharacters(value),
            !value.contains(";"),
            !hasBlankEdge(value)
        else {
            return .invalidValue
        }

        guard name.utf8.count + value.utf8.count <= maximumNameValueLength else {
            return .tooLarge
        }

        return nil
    }

    /// Whether `attribute` is a single label, which is never allowed, with a list or without one,
    /// or a rule of `publicSuffixList`. See `resolveDomain`.
    static func isPublicSuffixOrSingleLabel(
        _ attribute: String,
        publicSuffixList: Internals.PublicSuffixList?
    ) -> Bool {
        !attribute.contains(".") || (publicSuffixList?.isPublicSuffix(attribute) ?? false)
    }

    static func hasControlCharacters(_ string: String) -> Bool {
        string.utf8.contains { $0 < 0x20 || $0 == 0x7F }
    }

    // MARK: - Private static methods

    private static func hasBlankEdge(_ string: String) -> Bool {
        guard let first = string.utf8.first, let last = string.utf8.last else {
            return false
        }

        return first == 0x20 || first == 0x09 || last == 0x20 || last == 0x09
    }

    private static func domainRejection(
        _ domain: String,
        hostOnly: Bool,
        publicSuffixList: Internals.PublicSuffixList?
    ) -> Rejection? {
        guard !domain.isEmpty else {
            return .invalidDomain
        }

        guard domain.utf8.count <= maximumAttributeValueLength else {
            return .tooLarge
        }

        guard isHostName(domain) else {
            return .invalidDomain
        }

        guard !hostOnly else {
            return nil
        }

        // Never a domain cookie for an address: `Domain` does not apply to one.
        guard !isIPAddress(domain) else {
            return .invalidDomain
        }

        return isPublicSuffixOrSingleLabel(domain, publicSuffixList: publicSuffixList) ? .publicSuffix : nil
    }

    private static func pathRejection(_ path: String) -> Rejection? {
        guard path.hasPrefix("/"), !hasControlCharacters(path), !path.contains(";") else {
            return .invalidPath
        }

        return path.utf8.count <= maximumAttributeValueLength ? nil : .tooLarge
    }

    /// Letters, digits, `-`, `_` and `.` in labels that are not empty, or an IPv6 literal.
    private static func isHostName(_ domain: String) -> Bool {
        if domain.contains(":") {
            return domain.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte) || byte == 0x3A || byte == 0x2E
            }
        }

        return domain.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2D || byte == 0x5F
                || byte == 0x2E
        } && !domain.split(separator: ".", omittingEmptySubsequences: false).contains { $0.isEmpty }
    }
}
