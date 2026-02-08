/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct EndpointNode: PropertyNode {

    let endpoint: String

    func make(_ make: inout Make) async throws {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("://") {
            guard let url = URL(string: normalized) else {
                throw EndpointError(context: .invalidURL, url: endpoint)
            }

            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw EndpointError(context: .invalidURL, url: endpoint)
            }

            try processFullURL(components: components, into: &make.requestConfiguration)
        } else {
            let needsSeparator = !["/", "?"].contains(where: normalized.starts(with:))
            let placeholderURLString = "https://placeholder.com\(needsSeparator ? "/": "")\(normalized)"

            guard let components = URLComponents(string: placeholderURLString) else {
                throw EndpointError(context: .invalidURL, url: endpoint)
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

private extension EndpointNode {

    func constructBaseURLString(from components: URLComponents, host: String) throws -> String {
        guard !host.isEmpty else {
            throw EndpointError(context: .invalidHost, url: endpoint)
        }

        var fullHost = host
        if let port = components.port {
            fullHost += ":\(port)"
        }

        let scheme = components.scheme ?? "https"
        return "\(scheme)://\(fullHost)"
    }

    func pathComponents(from components: URLComponents) -> [String] {
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

    func queries(from components: URLComponents) -> [QueryItem] {
        return components.queryItems?.compactMap { item in
            QueryItem(name: item.name, value: item.value ?? "")
        } ?? []
    }
}
