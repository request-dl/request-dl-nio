//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)
import Foundation

/// Translates a plain `URL` into the `BaseURL`/`Path`/query building blocks RequestDL already
/// uses to describe a request, so ``RDLImageLoader`` can accept a `URL` without a separate
/// request pipeline.
struct URLImageProperty: Property {

    let url: URL

    var body: some Property {
        BaseURL(URLScheme(url.scheme ?? "https"), host: hostWithPort)

        if !url.path.isEmpty {
            Path(url.path)
        }

        QueryItemsProperty(items: percentEncodedQueryItems)
    }

    private var hostWithPort: String {
        guard let host = url.host else {
            return ""
        }

        guard let port = url.port else {
            return host
        }

        return "\(host):\(port)"
    }

    /// - Important: Read as `percentEncodedQueryItems`, not `queryItems`. Everything RequestDL
    /// stores in ``RequestConfiguration/queries`` is expected to already be percent encoded (see
    /// its doc comment), so encoding it again would turn every `%20` in the URL into `%2520`.
    private var percentEncodedQueryItems: [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedQueryItems ?? []
    }
}

/// Appends a fixed list of already-resolved query items.
///
/// A plain `Property` leaf rather than a loop of ``Query`` inside a `@PropertyBuilder` block,
/// because `PropertyBuilder` has no `buildArray` and can't compose a variable-length list
/// from a `for` loop. Writing directly to `RequestConfiguration.queries`, as `Query`'s own
/// node does, handles a list whose length is only known once the `URL` is inspected.
private struct QueryItemsProperty: Property {

    private struct Node: PropertyNode {

        let items: [URLQueryItem]

        func make(_ make: inout Make) async throws {
            for item in items {
                make.requestConfiguration.queries.append(
                    QueryItem(name: item.name, value: item.value ?? "")
                )
            }
        }
    }

    var body: Never {
        bodyException()
    }

    let items: [URLQueryItem]

    static func _makeProperty(
        property: _GraphValue<QueryItemsProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(items: property.items))
    }
}

#endif
