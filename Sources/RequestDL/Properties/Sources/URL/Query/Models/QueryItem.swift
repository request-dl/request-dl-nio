/*
 See LICENSE for this package's licensing information.
*/

import Foundation

///  A struct that represents a single query item in a URL request.
public struct QueryItem: Sendable, Equatable, Hashable {

    // MARK: - Public properties

    /// The name of the query item.
    public let name: String

    /// The value associated with the query item.
    public let value: String

    // MARK: - Internal methods

    func build() -> QueryItem {
        .init(
            name: name,
            value: value
        )
    }
}

// MARK: - [QueryItem] extension

extension [QueryItem] {

    func appendingPrefixKey(_ key: String) -> [QueryItem] {
        map {
            .init(
                name: key + $0.name,
                value: $0.value
            )
        }
    }

    func addingRFC3986PercentEncoding(
        withAllowedCharacters allowedCharacters: CharacterSet = CharacterSet()
    ) -> [QueryItem] {
        map {
            .init(
                name: $0.name.addingRFC3986PercentEncoding(withAllowedCharacters: allowedCharacters),
                value: $0.value.addingRFC3986PercentEncoding(withAllowedCharacters: allowedCharacters)
            )
        }
    }

    func replacingWhitespace(with representable: String) -> [QueryItem] {
        map {
            .init(
                name: $0.name.replacingOccurrences(of: " ", with: representable),
                value: $0.value.replacingOccurrences(of: " ", with: representable)
            )
        }
    }

    func joined() -> String {
        map { "\($0.name)=\($0.value)" }
            .joined(separator: "&")
    }
}
