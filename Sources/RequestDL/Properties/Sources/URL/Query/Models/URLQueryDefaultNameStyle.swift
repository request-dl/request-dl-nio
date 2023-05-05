//
//  File.swift
//  
//
//  Created by Brenno on 01/05/23.
//

import Foundation

public struct URLQueryDefaultNameStyle: URLQueryNameStyle {

    public func callAsFunction(_ key: String) -> String {
        key
    }
}

extension URLQueryNameStyle where Self == URLQueryDefaultNameStyle {

    public static var `default`: URLQueryDefaultNameStyle {
        URLQueryDefaultNameStyle()
    }
}

public struct QueryLiteralOptionalStyle: QueryOptionalStyle {

    public func callAsFunction() -> String? {
        "nil"
    }
}

extension QueryOptionalStyle where Self == QueryLiteralOptionalStyle {

    public static var literal: QueryLiteralOptionalStyle {
        .init()
    }
}

public struct QueryEmptyOptionalStyle: QueryOptionalStyle {

    public func callAsFunction() -> String? {
        nil
    }
}

extension QueryOptionalStyle where Self == QueryEmptyOptionalStyle {

    public static var empty: QueryEmptyOptionalStyle {
        .init()
    }
}

public struct QueryEmptyBracketsArrayStyle: QueryArrayStyle {

    public func callAsFunction(_ index: Int) -> String {
        "[]"
    }
}

extension QueryArrayStyle where Self == QueryEmptyBracketsArrayStyle {

    static var emptyBrackets: QueryEmptyBracketsArrayStyle {
        QueryEmptyBracketsArrayStyle()
    }
}

public struct QueryEmptyArrayStyle: QueryArrayStyle {

    public func callAsFunction(_ index: Int) -> String {
        ""
    }
}

extension QueryArrayStyle where Self == QueryEmptyArrayStyle {

    static var empty: QueryEmptyArrayStyle {
        QueryEmptyArrayStyle()
    }
}

public struct QueryBracketsDictionaryStyle: QueryDictionaryStyle {

    public func callAsFunction(_ key: String) -> String {
        "[\(key)]"
    }
}

extension QueryDictionaryStyle where Self == QueryBracketsDictionaryStyle {

    public static var brackets: QueryBracketsDictionaryStyle {
        QueryBracketsDictionaryStyle()
    }
}

public struct QueryDotsDictionaryStyle: QueryDictionaryStyle {

    public func callAsFunction(_ key: String) -> String {
        ".\(key)"
    }
}

extension QueryDictionaryStyle where Self == QueryDotsDictionaryStyle {

    public static var dots: QueryDotsDictionaryStyle {
        QueryDotsDictionaryStyle()
    }
}

public struct QueryPercentEscapingStyle: QueryWhitespaceStyle {

    public func callAsFunction() -> String {
        "%20"
    }
}

extension QueryWhitespaceStyle where Self == QueryPercentEscapingStyle {

    public static var percentEscaping: QueryPercentEscapingStyle {
        .init()
    }
}

extension String {

    func addingQueryPercentEncoding() -> String {
        addingPercentEncoding(withAllowedCharacters: ._urlQueryAllowed) ?? self
    }
}

extension CharacterSet {
    /// Creates a CharacterSet from RFC 3986 allowed characters.
    ///
    /// RFC 3986 states that the following characters are "reserved" characters.
    ///
    /// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
    /// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
    ///
    /// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
    /// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
    /// should be percent-escaped in the query string.
    static let _urlQueryAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        let encodableDelimiters = CharacterSet(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

        return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
    }()
}
