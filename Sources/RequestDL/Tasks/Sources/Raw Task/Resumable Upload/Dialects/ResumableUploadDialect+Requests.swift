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

    /// A request to `url` that keeps what the caller set up for the request it is built from, but
    /// not what described its body: the base, the headers about the body, the body itself.
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

        for name in headers.names where Self.headersDescribingTheBody.contains(name.lowercased()) {
            configuration.headers.remove(name: name)
        }

        return configuration
    }

    /// `location` as an absolute URL, `location` being what a server answered with, which may be
    /// relative to the URL the request went to.
    func resolving(location: String) -> String? {
        let trimmed = location.trimming(where: \.isWhitespace)

        guard !trimmed.isEmpty else {
            return nil
        }

        if let absolute = URLComponents(string: trimmed), absolute.scheme != nil, absolute.host != nil {
            return trimmed
        }

        guard let base = URL(string: url), let resolved = URL(string: trimmed, relativeTo: base) else {
            return nil
        }

        return resolved.absoluteString
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
