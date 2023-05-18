/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PayloadNode: PropertyNode {

    enum Source {
        case data(DataPayloadFactory)
        case url(FilePayloadFactory)
        case string(StringPayloadFactory)
        case encoded(EncodablePayloadFactory)
        case json(JSONPayloadFactory)

        var isURLEncodedCompatible: Bool {
            switch self {
            case .encoded, .json:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Internal properties

    let source: Source
    let urlEncoder: URLEncoder
    let partLength: Int?

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        switch source {
        case .data(let factory):
            try makeDefault(factory, in: &make)
        case .string(let factory):
            try makeDefault(factory, in: &make)
        case .url(let factory):
            try makeDefault(factory, in: &make)
        case .encoded(let factory):
            try makeEncodableEncodedIfNeeded(factory, in: &make)
        case .json(let factory):
            try makeJSONEncodedIfNeeded(factory, in: &make)
        }
    }

    // MARK: - Private methods

    private func makeEncodableEncodedIfNeeded(
        _ factory: EncodablePayloadFactory,
        in make: inout Make
    ) throws {
        guard needsToEncodeInURL(factory, headers: make.request.headers) else {
            return try makeDefault(factory, in: &make)
        }

        let json = try JSONSerialization.jsonObject(
            with: try factory.encode(JSONEncoder()),
            options: [.fragmentsAllowed]
        )

        try encodeJSON(
            json: json,
            factory: factory,
            in: &make
        )
    }

    private func makeJSONEncodedIfNeeded(
        _ factory: JSONPayloadFactory,
        in make: inout Make
    ) throws {
        guard needsToEncodeInURL(factory, headers: make.request.headers) else {
            return try makeDefault(factory, in: &make)
        }

        try encodeJSON(
            json: factory.jsonObject,
            factory: factory,
            in: &make
        )
    }

    private func encodeJSON(
        json: Any,
        factory: PayloadFactory,
        in make: inout Make
    ) throws {
        switch json {
        case let array as [Any]:
            try makeArrayURLEncoded(array, in: &make)
        case let dictionary as [String: Any]:
            try makeDictionaryURLEncoded(dictionary, in: &make)
        default:
            try makeDefault(factory, in: &make)
        }
    }

    private func needsToEncodeInURL(_ factory: PayloadFactory, headers: HTTPHeaders) -> Bool {
        if let contentType = factory.contentType {
            return isFormURLEncoded(String(contentType))
        }

        return headers.contains(name: "Content-Type") {
            isFormURLEncoded($0)
        }
    }

    private func isFormURLEncoded(_ string: String) -> Bool {
        string.range(of: "x-www-form-urlencoded", options: .caseInsensitive) != nil
    }

    private func makeDictionaryURLEncoded(_ value: [String: Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (key, value) in value {
            let encodedQueries = try urlEncoder.encode(value, forKey: key)
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    private func makeArrayURLEncoded(_ value: [Any], in make: inout Make) throws {
        var queries = [QueryItem]()

        for (index, value) in value.enumerated() {
            let encodedQueries = try urlEncoder.encode(value, forKey: String(index))
            queries.append(contentsOf: encodedQueries)
        }

        makeQueries(queries, in: &make)
    }

    private func makeQueries(_ queries: [QueryItem], in make: inout Make) {
        let queries = queries.map { $0.build() }

        if outputPayloadInURL(make.request.method) {
            make.request.queries.append(contentsOf: queries)
        } else {
            // TODO: - Needs to update header with charset
            make.request.body = Internals.Body(partLength, buffers: [
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

    private func makeDefault(_ factory: PayloadFactory, in make: inout Make) throws {
        if let contentType = factory.contentType {
            make.request.headers.set(
                name: "Content-Type",
                value: String(contentType)
            )
        } else if make.request.headers.first(name: "Content-Type") == nil {
            make.request.headers.set(
                name: "Content-Type",
                value: String(ContentType.octetStream)
            )
        }

        let buffer = try factory()

        make.request.headers.setContentLengthIfNeeded(buffer.estimatedBytes)
        make.request.body = Internals.Body(partLength, buffers: [buffer])
    }
}
