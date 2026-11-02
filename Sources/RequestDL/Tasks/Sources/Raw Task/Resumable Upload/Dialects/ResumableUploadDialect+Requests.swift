//
// See LICENSE for this package's licensing information.
//

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

    /// What identifies the caller to the server it wrote the request for, which another server has
    /// no business receiving.
    private static let headersIdentifyingTheCaller: Set<String> = [
        "authorization",
        "cookie",
        "proxy-authorization",
        "origin",
    ]

    /// A request to `url` that keeps what the caller set up for the request it is built from, but
    /// not what described its body: the base, the headers about the body, the body itself.
    ///
    /// When `url` is not on the origin of this request, which only happens when the server chose
    /// it, the headers that identify the caller stay behind too, unless the caller asked for them
    /// to be forwarded.
    func derived(method: String, url: String) -> RequestConfiguration {
        var configuration = self

        configuration.baseURL = url
        configuration.pathComponents = []
        configuration.queries = []
        configuration.method = method
        configuration.body = nil
        configuration.cachePolicy = []
        configuration.cacheStrategy = .ignoreCachedData
        configuration.compression = nil
        configuration.shouldCompressBodyData = nil

        let keepsCredentials = forwardsCredentialsToOtherOrigins || Self.isSameOrigin(self.url, url)

        for name in headers.names {
            let lowercased = name.lowercased()

            if Self.headersDescribingTheBody.contains(lowercased)
                || (!keepsCredentials && Self.headersIdentifyingTheCaller.contains(lowercased))
            {
                configuration.headers.remove(name: name)
            }
        }

        return configuration
    }

    /// `location` as an absolute URL, `location` being what a server answered with, which may be
    /// relative to the URL the request went to.
    ///
    /// `nil` when it is not an `http` or `https` URL, or when it would take a request that went
    /// over `https` to `http`: the rest of the upload would then travel in the clear.
    func resolving(location: String) -> String? {
        let trimmed = location.trimming(where: \.isWhitespace)

        guard !trimmed.isEmpty else {
            return nil
        }

        let resolved: String

        if let absolute = URLComponents(string: trimmed), absolute.scheme != nil, absolute.host != nil {
            resolved = trimmed
        } else if let base = URL(string: url), let relative = URL(string: trimmed, relativeTo: base) {
            resolved = relative.absoluteString
        } else {
            return nil
        }

        guard let scheme = URL(string: resolved)?.scheme?.lowercased(), Self.defaultPorts[scheme] != nil else {
            return nil
        }

        if URL(string: url)?.scheme?.lowercased() == "https", scheme != "https" {
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
