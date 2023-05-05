//
//  File.swift
//  
//
//  Created by Brenno on 01/05/23.
//

import Foundation

public struct URLEncoder {

    public var dateStyle: URLQueryDateStyle = .iso8601

    public var nameStyle: URLQueryNameStyle = .default

    public var dataStyle: URLQueryDataStyle = .base64

    public var boolStyle: URLQueryBoolStyle = .literal

    public var optionalStyle: URLQueryOptionalStyle = .literal

    public var arrayStyle: URLQueryArrayStyle = .empty

    public var dictionaryStyle: URLQueryDictionaryStyle = .brackets

    public var whitespaceStyle: URLQueryWhitespaceStyle = .percentEscaping

    public init() {}
}

extension URLEncoder {

    private func rawEncode(_ value: Any, for name: String) -> [Internals.Query] {
        var queries = [Internals.Query]()

        let name = nameStyle(name)

        switch value {
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                let key = dictionaryStyle(key)
                queries.append(contentsOf: rawEncode(value, for: name + key))
            }
        case let array as [Any]:
            for (index, value) in array.enumerated() {
                let key = arrayStyle(index)
                queries.append(contentsOf: rawEncode(value, for: name + key))
            }
        case let date as Date:
            queries.append(.init(
                name: name,
                value: dateStyle(date)
            ))
        case let flag as Bool:
            queries.append(.init(
                name: name,
                value: boolStyle(flag)
            ))
        case let wrapped as OptionalLiteral:
            switch wrapped.value {
            case .some(let value):
                queries.append(contentsOf: rawEncode(value, for: name))
            case .none:
                if let nilValue = optionalStyle() {
                    queries.append(.init(
                        name: name,
                        value: nilValue
                    ))
                }
            }
        default:
            queries.append(.init(
                name: name,
                value: "\(value)"
            ))
        }

        return queries
    }

    func encode(_ value: Any, for name: String) -> [Internals.Query] {
        rawEncode(value, for: name).map {
            .init(
                name: $0.name.replacingOccurrences(of: " ", with: whitespaceStyle()),
                value: $0.value.replacingOccurrences(of: " ", with: whitespaceStyle())
            )
        }
    }
}

private protocol OptionalLiteral {

    var value: Any? { get }
}

extension Optional: OptionalLiteral {

    fileprivate var value: Any? {
        switch self {
        case .some(let wrapped):
            return wrapped
        case .none:
            return nil
        }
    }
}
