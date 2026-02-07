/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct URLNode: PropertyNode {

    let endpoint: String

    func make(_ make: inout Make) async throws {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: normalized) {
            try process(url: url, into: &make.request)
            return
        }

        if let url = URL(string: "https://\(normalized)") {
            try process(url: url, into: &make.request)
            return
        }

        try process(relativePath: normalized, into: &make.request)
    }

    // MARK: - Private Methods

    private func process(url: URL, into request: inout Internals.Request) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw EndpointError(
                context: .invalidURL,
                url: endpoint
            )
        }

        let hasHost = components.host != nil

        if hasHost {
            try overwrite(with: components, into: &request)
        } else {
            try append(with: components, into: &request)
        }
    }

    private func process(relativePath: String, into request: inout Internals.Request) throws {
        guard let components = URLComponents(string: "https://placeholder.com\(relativePath)") else {
            throw EndpointError(
                context: .invalidURL,
                url: endpoint
            )
        }

        try append(with: components, into: &request)
    }

    // MARK: - Overwrite Logic (URL with host)

    private func overwrite(with components: URLComponents, into request: inout Internals.Request) throws {
        request.baseURL = try baseURL(from: components)
        request.pathComponents = pathComponents(from: components)
        request.queries = queries(from: components)
    }

    // MARK: - Append Logic (path + queries only)

    private func append(with components: URLComponents, into request: inout Internals.Request) throws {
        if !components.path.isEmpty {
            if components.path == "/" && !(request.pathComponents.last?.hasSuffix("/") ?? false) {
                request.pathComponents.append("/")
            } else {
                request.pathComponents += pathComponents(from: components)
            }
        }

        request.queries += queries(from: components)
    }
}

private extension URLNode {

    func baseURL(from components: URLComponents) throws -> String {
        guard var host = components.host else {
            throw EndpointError(
                context: .invalidHost,
                url: endpoint
            )
        }

        if let port = components.port {
            host += ":" + String(port)
        }

        return (components.scheme ?? "https") + "://" + host
    }

    func pathComponents(from components: URLComponents) -> [String] {
        var pathComponents = components.path
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .map(String.init)

        if components.path.hasSuffix("/") {
            if !pathComponents.isEmpty {
                pathComponents[pathComponents.count - 1] += "/"
            } else {
                pathComponents.append("/")
            }
        }

        return pathComponents
    }

    func queries(from components: URLComponents) -> [Internals.Query] {
        components.queryItems?.map {
            Internals.Query(name: $0.name, value: $0.value ?? "")
        } ?? []
    }
}
