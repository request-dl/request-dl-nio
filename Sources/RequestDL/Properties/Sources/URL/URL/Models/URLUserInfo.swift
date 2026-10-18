//
// See LICENSE for this package's licensing information.
//

/// The user name and the password a URL can carry in its authority (`user:password@host`).
///
/// Credentials do not belong in a URL: the request does not send them, and a URL ends up in
/// errors and logs. `FlexibleURL`, `BaseURL` and `Configured` reject them, and what they put in
/// an error has them redacted.
///
/// Only the authority is looked at: the part of a complete URL between `"://"` and the first
/// `"/"`, `"?"` or `"#"`. An `@` in a path, a query or a fragment is not userinfo, and a relative
/// value has no authority.
enum URLUserInfo {

    /// What takes the place of the user name and the password in a redacted value.
    static let placeholder = "REDACTED"

    /// Whether a complete `scheme://authority/...` value carries userinfo in its authority.
    static func isPresent(in url: String) -> Bool {
        authority(of: url).map { url[$0].contains("@") } ?? false
    }

    /// Whether a host, as `BaseURL` takes it (`host`, `host:port`), carries userinfo.
    static func isPresent(inHost host: String) -> Bool {
        host.prefix { !isAuthorityEnd($0) }.contains("@")
    }

    /// `url` with the userinfo of its authority replaced by ``placeholder``, or `url` itself when
    /// it has none.
    static func redacting(url: String) -> String {
        guard let authority = authority(of: url), let at = url[authority].lastIndex(of: "@") else {
            return url
        }

        return String(url[..<authority.lowerBound]) + placeholder + String(url[at...])
    }

    /// `host` with the userinfo replaced by ``placeholder``, or `host` itself when it has none.
    /// A host that has the scheme in front of it is a URL, and is redacted as one.
    static func redacting(host: String) -> String {
        if authority(of: host) != nil {
            return redacting(url: host)
        }

        let end = host.firstIndex(where: isAuthorityEnd) ?? host.endIndex

        guard let at = host[..<end].lastIndex(of: "@") else {
            return host
        }

        return placeholder + String(host[at...])
    }

    // MARK: - Private methods

    private static func isAuthorityEnd(_ character: Character) -> Bool {
        character == "/" || character == "?" || character == "#"
    }

    /// The range of the authority of a complete URL, `nil` for a value that is not one. Only the
    /// part before any query or fragment can hold a `"://"`: a relative path whose query value
    /// has one (`"/search?redirect=http://example.com"`) is not a complete URL.
    private static func authority(of url: String) -> Range<String.Index>? {
        let structuralEnd = url.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? url.endIndex

        guard let separator = schemeSeparator(in: url, before: structuralEnd) else {
            return nil
        }

        let end = url[separator.upperBound...].firstIndex(where: isAuthorityEnd) ?? url.endIndex

        return separator.upperBound..<end
    }

    /// `Collection.firstRange(of:)` starts at macOS 13, and this package at macOS 12.
    private static func schemeSeparator(
        in url: String,
        before end: String.Index
    ) -> Range<String.Index>? {
        var index = url.startIndex

        while index < end {
            if url[index..<end].hasPrefix("://") {
                return index..<url.index(index, offsetBy: 3)
            }

            index = url.index(after: index)
        }

        return nil
    }
}
