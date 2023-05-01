//
//  File.swift
//  
//
//  Created by Brenno on 01/05/23.
//

import Foundation

public protocol QueryStyle {

    func encode<Value>(
        _ value: Value,
        for name: String
    ) -> QueryEncoded
}

protocol QueryItemBuilder {

    func callAsFunction() -> [URLQueryItem]
}

public enum QueryEncoded {
    case item(QueryItem)
    case collection(QueryCollection)
    case none
}

public struct QueryItem {

    let name: String
    let value: String

    public init(
        name: String,
        value: String
    ) {
        self.name = name
        self.value = value
    }
}

extension QueryItem: QueryItemBuilder {

    func callAsFunction() -> [URLQueryItem] {
        [.init(
            name: name,
            value: value
        )]
    }
}

public struct QueryCollection {

    private let name: String
    private var items: [QueryItem]
    private var groupStrategy: (String) -> String

    public init(_ name: String, groupingBy strategy: @escaping (String) -> String) {
        self.name = name
        self.items = []
        self.groupStrategy = strategy
    }

    public mutating func append(_ item: QueryItem) {
        items.append(item)
    }

    public mutating func append(contentsOf collection: [QueryItem]) {
        items.append(contentsOf: collection)
    }

    func flat() -> [QueryItem] {
        items.map {
            .init(
                name: name + groupStrategy($0.name),
                value: $0.value
            )
        }
    }
}

extension QueryCollection: QueryItemBuilder {

    func callAsFunction() -> [URLQueryItem] {
        flat().map {
            .init(
                name: $0.name,
                value: $0.value
            )
        }
    }
}
