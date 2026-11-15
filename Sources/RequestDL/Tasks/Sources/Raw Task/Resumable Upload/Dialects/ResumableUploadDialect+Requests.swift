//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import struct FoundationEssentials.URL
import struct FoundationEssentials.URLComponents
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

extension RequestConfiguration {

    /// Headers that describe the body of a request, or the way it is carried, so they belong to the
    /// request that created the upload and not to the ones that ask about it or send its bytes.
    private static let headersDescribingTheBody: Set<String> = [
        "content-type",
        "content-length",
        "content-encoding",
        "content-language",
        "content-location",
        "content-md5",
        "content-range",
        "digest",
        "expect",
        "transfer-encoding",
        "tus-resumable",
        "upload-complete",
        "upload-length",
        "upload-offset",
        "upload-metadata",
        "upload-defer-length",
    ]

    /// What a request leaves behind when it goes to another origin than the one it was written for:
    /// the very list a redirect to another origin applies, so the two never disagree about what
    /// belongs to the origin it came from.
    private static let headersLeftBehindAtAnotherOrigin = Set(
        Internals.RedirectSanitizer.crossOriginHeaders.map { $0.lowercased() }
    )

    /// The one of those that is not a credential: it names the virtual host of the origin the
    /// request was written for, which is wrong at any other, whoever is trusted with the rest.
    private static let headersNeverSentToAnotherOrigin: Set<String> = ["host"]

    /// A request to `url` that keeps what the caller set up for the request it is built from, but
    /// not what described its body: the base, the headers about the body, the body itself.
    ///
    /// When `url` is not on the origin of this request, which only happens when the server chose
    /// it, the headers that identify the caller stay behind too, unless the caller asked for them
    /// to be forwarded (`Host` stays behind regardless, see ``headersNeverSentToAnotherOrigin``).
    ///
    /// `url` is kept exactly as it is, to the last character: a server that answers with
    /// `/files/abc/` has a resource at that URL, and not at `/files/abc`.
    func derived(method: String, url: String) -> RequestConfiguration {
        var configuration = self

        configuration.baseURL = url
        configuration.exactURL = url
        configuration.pathComponents = []
        configuration.queries = []
        configuration.method = method
        configuration.body = nil
        configuration.cachePolicy = []
        configuration.cacheStrategy = .ignoreCachedData
        configuration.compression = nil
        configuration.shouldCompressBodyData = nil

        let leftBehind: Set<String>

        if Self.isSameOrigin(self.url, url) {
            leftBehind = []
        } else if forwardsCredentialsToOtherOrigins {
            leftBehind = Self.headersNeverSentToAnotherOrigin
        } else {
            leftBehind = Self.headersLeftBehindAtAnotherOrigin
        }

        for name in headers.names {
            let lowercased = name.lowercased()

            if Self.headersDescribingTheBody.contains(lowercased) || leftBehind.contains(lowercased) {
                configuration.headers.remove(name: name)
            }
        }

        return configuration
    }

    /// `location` as an absolute URL, `location` being what a server answered with, which may be
    /// relative to the URL that answered: `answeredFrom`, the URL the response reports, and the URL
    /// of this request when it is not known. `.urlSession` reports the final URL of a request that
    /// was redirected; `.nio` reports the one it was sent to, so there the two are the same.
    ///
    /// `nil` when it is not an `http` or `https` URL, or when it would take a request that went
    /// over `https` to `http`: the rest of the upload would then travel in the clear.
    func resolving(location: String, answeredFrom: String? = nil) -> String? {
        let trimmed = location.trimming(where: \.isWhitespace)

        guard !trimmed.isEmpty else {
            return nil
        }

        let resolved: String

        // Relative to where the answer came from: a creation that was redirected is answered by
        // another URL than the one it was sent to.
        let answered = answeredFrom.flatMap { $0.isEmpty ? nil : $0 } ?? url

        if let absolute = URLComponents(string: trimmed), absolute.scheme != nil, absolute.host != nil {
            resolved = trimmed
        } else if let base = URL(string: answered), let relative = URL(string: trimmed, relativeTo: base) {
            resolved = relative.absoluteString
        } else {
            return nil
        }

        guard let scheme = URL(string: resolved)?.scheme?.lowercased(), Self.defaultPorts[scheme] != nil else {
            return nil
        }

        let wentOverHTTPS = [url, answered].contains { URL(string: $0)?.scheme?.lowercased() == "https" }

        if wentOverHTTPS, scheme != "https" {
            return nil
        }

        return resolved
    }

    private static let defaultPorts = ["http": 80, "https": 443]

    /// Whether both URLs have the same scheme, host and port (RFC 6454). A URL that cannot be read
    /// is on no origin.
    private static func isSameOrigin(_ first: String, _ second: String) -> Bool {
        guard let first = origin(of: first), let second = origin(of: second) else {
            return false
        }

        return first == second
    }

    private static func origin(of string: String) -> [String]? {
        guard
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            let host = url.host?.lowercased(),
            let port = url.port ?? defaultPorts[scheme]
        else {
            return nil
        }

        return [scheme, host, String(port)]
    }
}

extension HTTPHeaders {

    /// The non-negative integer in the header `name`, as an HTTP structured field carries it;
    /// `nil` when it is absent or is anything else.
    func integer(for name: String) -> Int64? {
        guard let value = first(name: name)?.trimming(where: \.isWhitespace), let number = Int64(value) else {
            return nil
        }

        return number >= .zero ? number : nil
    }

    /// The boolean in the header `name`, as an HTTP structured field carries it (`?1`, `?0`);
    /// `nil` when it is absent or is anything else.
    func boolean(for name: String) -> Bool? {
        switch first(name: name)?.trimming(where: \.isWhitespace) {
        case "?1":
            return true
        case "?0":
            return false
        default:
            return nil
        }
    }
}
