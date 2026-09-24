//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

struct FlexibleURLNode: PropertyNode {

    let url: String

    func make(_ make: inout Make) async throws {
        // `Character.isWhitespace` already covers newlines, so this is the whole of
        // `.whitespacesAndNewlines` without needing `Foundation.CharacterSet`.
        let normalized = url.trimming(where: \.isWhitespace)

        // Only the part before any query/fragment can carry a `scheme://authority`: RFC 3986's
        // grammar puts `"?"`/`"#"` after the authority, never inside it. Searching the *whole*
        // string for `"://"` instead misclassified an ordinary relative path whose query value
        // happens to contain it, e.g. `"/search?redirect=http://evil.example.com"`, as a full
        // URL. That took the `processFullURL` branch below, which -- since this string still has
        // no `host` once actually parsed -- left `baseURL` untouched but still appended with
        // `fromStart: true` instead of `fromStart: false`, prepending this node's path ahead of
        // whatever the tree had already contributed instead of appending after it.
        let structuralEnd = normalized.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? normalized.endIndex
        let isFullURL = normalized[..<structuralEnd].contains("://")

        if isFullURL {
            guard let url = URL(string: normalized) else {
                throw FlexibleURLError(context: .invalidURL, url: url)
            }

            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw FlexibleURLError(context: .invalidURL, url: self.url)
            }

            try processFullURL(components: components, into: &make.requestConfiguration)
        } else {
            let needsSeparator = !["/", "?"].contains(where: normalized.starts(with:))
            let placeholderURLString = "https://placeholder.com\(needsSeparator ? "/": "")\(normalized)"

            guard let components = URLComponents(string: placeholderURLString) else {
                throw FlexibleURLError(context: .invalidURL, url: url)
            }

            try appendPathAndQueries(components: components, into: &make.requestConfiguration, fromStart: false)
        }
    }

    // MARK: - Private Methods

    private func processFullURL(components: URLComponents, into request: inout RequestConfiguration) throws {
        if let host = components.host {
            request.baseURL = try constructBaseURLString(from: components, host: host)
        }

        try appendPathAndQueries(components: components, into: &request, fromStart: true)
    }

    private func appendPathAndQueries(
        components: URLComponents,
        into request: inout RequestConfiguration,
        fromStart: Bool
    ) throws {
        let newPathComponents = pathComponents(from: components)

        if !newPathComponents.isEmpty {
            if fromStart {
                request.pathComponents = newPathComponents + request.pathComponents
            } else {
                request.pathComponents += newPathComponents
            }
        }

        if fromStart {
            request.queries = queries(from: components) + request.queries
        } else {
            request.queries += queries(from: components)
        }
    }
}

extension FlexibleURLNode {

    fileprivate func constructBaseURLString(from components: URLComponents, host: String) throws -> String {
        guard !host.isEmpty else {
            throw FlexibleURLError(context: .invalidHost, url: url)
        }

        var fullHost = host
        if let port = components.port {
            fullHost += ":\(port)"
        }

        let scheme = components.scheme ?? "https"
        return "\(scheme)://\(fullHost)"
    }

    fileprivate func pathComponents(from components: URLComponents) -> [String] {
        var splitComponents = Array(
            components.path
                .split(separator: "/")
                .lazy
                .filter { !$0.isEmpty }
                .map(String.init)
        )

        if components.path.hasSuffix("/") {
            if !splitComponents.isEmpty {
                splitComponents[splitComponents.count - 1] += "/"
            } else if components.path == "/" {
                splitComponents.append("/")
            }
        }

        return splitComponents
    }

    /// - Important: `percentEncodedQueryItems`, not `queryItems`. `RequestConfiguration.url`
    /// joins query items as-is, expecting them already percent encoded, so the decoded form
    /// turned `q=a%26b` into `q=a&b` (two parameters), `%3D` into a live `=`, and `%2B` into a
    /// `+` a server reads as a space.
    fileprivate func queries(from components: URLComponents) -> [QueryItem] {
        components.percentEncodedQueryItems?.compactMap { item in
            QueryItem(name: item.name, value: item.value ?? "")
        } ?? []
    }
}
