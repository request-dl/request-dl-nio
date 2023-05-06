/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct PayloadNode: PropertyNode {

    let isURLEncodedCompatible: Bool
    let buffer: () -> BufferProtocol
    let urlEncoder: URLEncoder

    func make(_ make: inout Make) async throws {
        guard
            isURLEncodedCompatible,
            isURLEncoded(make.request.headers),
            let data = buffer().getData()
        else {
            make.request.body = Internals.Body(buffers: [buffer()])
            return
        }

        let json = try jsonObject(data)

        switch json {
        case let value as [String: Any]:
            try makeDictionaryURLEncoded(value, in: &make)
        case let value as [Any]:
            try makeArrayURLEncoded(value, in: &make)
        default:
            make.request.body = Internals.Body(buffers: [buffer()])
        }
    }
}

private extension PayloadNode {

    func isURLEncoded(_ headers: Internals.Headers) -> Bool {
        headers.contains("x-www-form-urlencoded", forKey: "Content-Type")
    }

    func jsonObject(_ data: Data) throws -> Any {
        var readingOptions = JSONSerialization.ReadingOptions.fragmentsAllowed

        #if canImport(Darwin)
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            readingOptions.insert(.json5Allowed)
        }
        #endif

        return try JSONSerialization.jsonObject(with: data, options: readingOptions)
    }
}

private extension PayloadNode {

    func makeDictionaryURLEncoded(_ value: [String: Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (key, value) in value {
            let encodedQueries = try urlEncoder.encode(value, forKey: key)
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    func makeArrayURLEncoded(_ value: [Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (index, value) in value.enumerated() {
            let encodedQueries = try urlEncoder.encode(value, forKey: "\(index)")
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    private func makeQueries(_ queries: [QueryItem], in make: inout Make) {
        let queries = queries.map { $0.build() }

        if outputPayloadInURL(make.request.method) {
            make.request.queries.append(contentsOf: queries)
        } else {
            make.request.body = Internals.Body(buffers: [
                Internals.DataBuffer(queries.joined().utf8)
            ])
        }
    }

    private func outputPayloadInURL(_ method: String?) -> Bool {
        guard let method else {
            return false
        }

        return ["GET", "HEAD"].first(where: {
            method.caseInsensitiveCompare($0) == .orderedSame
        }) != nil
    }
}
