//
//  File.swift
//  
//
//  Created by Brenno on 01/05/23.
//

import Foundation

public struct QueryFormatter {

    public var dateStyle: QueryDateStyle = .iso8601

    public var nameStyle: QueryNameStyle = .default

    public var dataStyle: QueryDataStyle = .base64

    public var boolStyle: QueryBoolStyle = .literal

    public var optionalStyle: QueryOptionalStyle = .default

    public var arrayStyle: QueryArrayStyle = .empty

    public var dictionaryStyle: QueryDictionaryStyle = .brackets

    public var whitespaceStyle: QueryWhitespaceStyle = .percentEscaping

    public init() {}
}

public protocol QueryNameStyle {

    func callAsFunction(_ key: String) -> String
}

public struct DefaultQueryNameStyle: QueryNameStyle {

    public func callAsFunction(_ key: String) -> String {
        key
    }
}

extension QueryNameStyle where Self == DefaultQueryNameStyle {

    public static var `default`: DefaultQueryNameStyle {
        DefaultQueryNameStyle()
    }
}

public protocol QueryDateStyle {

    func callAsFunction(_ date: Date) -> String
}

public struct CustomQueryDateStyle: QueryDateStyle {

    let format: String
    let locale: Locale?
    let timeZone: TimeZone?
    let calendar: Calendar?

    public func callAsFunction(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format

        if let locale {
            formatter.locale = locale
        }

        if let timeZone {
            formatter.timeZone = timeZone
        }

        if let calendar {
            formatter.calendar = calendar
        }

        return formatter.string(from: date)
    }
}

extension QueryDateStyle where Self == CustomQueryDateStyle {

    public static func custom(
        _ format: String,
        locale: Locale? = nil
    ) -> CustomQueryDateStyle {
        CustomQueryDateStyle(
            format: format,
            locale: locale,
            timeZone: nil,
            calendar: nil
        )
    }

    public static func custom(
        _ format: String,
        locale: Locale? = nil,
        timeZone: TimeZone,
        calendar: Calendar
    ) -> CustomQueryDateStyle {
        CustomQueryDateStyle(
            format: format,
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
    }
}

public struct QueryISO8601DateStyle: QueryDateStyle {

    let timeZone: TimeZone?

    public func callAsFunction(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()

        if let timeZone {
            formatter.timeZone = timeZone
        }

        return formatter.string(from: date)
    }
}

extension QueryDateStyle where Self == QueryISO8601DateStyle {

    public static var iso8601: QueryISO8601DateStyle {
        .init(timeZone: nil)
    }

    public static func iso8601(
        timeZone: TimeZone?
    ) -> QueryISO8601DateStyle {
        .init(timeZone: timeZone)
    }
}

public protocol QueryDataStyle {

    func callAsFunction(_ data: Data) -> String
}

public struct QueryBase64DataStyle: QueryDataStyle {

    let options: Data.Base64EncodingOptions?

    public func callAsFunction(_ data: Data) -> String {
        if let options {
            return data.base64EncodedString(options: options)
        } else {
            return data.base64EncodedString()
        }
    }
}

extension QueryDataStyle where Self == QueryBase64DataStyle {

    public static var base64: QueryBase64DataStyle {
        .init(options: nil)
    }

    public static func base64(options: Data.Base64EncodingOptions) -> QueryBase64DataStyle {
        .init(options: options)
    }
}

public protocol QueryBoolStyle {

    func callAsFunction(_ flag: Bool) -> String
}

public struct QueryLiteralBoolStyle: QueryBoolStyle {

    public func callAsFunction(_ flag: Bool) -> String {
        if flag {
            return "true"
        } else {
            return "false"
        }
    }
}

extension QueryBoolStyle where Self == QueryLiteralBoolStyle {

    public static var literal: QueryLiteralBoolStyle {
        QueryLiteralBoolStyle()
    }
}

public struct QueryNumericBoolStyle: QueryBoolStyle {

    public func callAsFunction(_ flag: Bool) -> String {
        if flag {
            return "1"
        } else {
            return "0"
        }
    }
}

extension QueryBoolStyle where Self == QueryNumericBoolStyle {

    public static var numeric: QueryNumericBoolStyle {
        QueryNumericBoolStyle()
    }
}

public protocol QueryOptionalStyle {

    func callAsFunction() -> String?
}

public struct QueryDefaultStyle: QueryOptionalStyle {

    public func callAsFunction() -> String? {
        "nil"
    }
}

extension QueryOptionalStyle where Self == QueryDefaultStyle {

    public static var `default`: QueryDefaultStyle {
        .init()
    }
}

public protocol QueryArrayStyle {

    func callAsFunction(_ index: Int) -> String
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

public protocol QueryDictionaryStyle {

    func callAsFunction(_ key: String) -> String
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

public protocol QueryWhitespaceStyle {

    func callAsFunction() -> String
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

extension QueryFormatter: QueryStyle {

    private func applyWhitespaceStyle(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: whitespaceStyle())
    }

    fileprivate func decodeDate(_ name: String, _ date: Date) -> QueryEncoded {
        return .item(.init(
            name: name,
            value: applyWhitespaceStyle(dateStyle(date))
        ))
    }

    fileprivate func decodeData(_ name: String, _ data: Data) -> QueryEncoded {
        return .item(.init(
            name: name,
            value: applyWhitespaceStyle(dataStyle(data))
        ))
    }

    fileprivate func decodeBool(_ name: String, _ flag: Bool) -> QueryEncoded {
        return .item(.init(
            name: name,
            value: applyWhitespaceStyle(boolStyle(flag))
        ))
    }

    fileprivate func decodeDictionary(_ name: String, _ dictionary: [AnyHashable : Any]) -> QueryEncoded {
        var collection = QueryCollection(applyWhitespaceStyle(name)) {
            applyWhitespaceStyle(dictionaryStyle($0))
        }

        for (key, value) in dictionary {
            let key = applyWhitespaceStyle("\(key)")

            switch encode(value, for: key) {
            case .collection(let valueCollection):
                collection.append(contentsOf: valueCollection.flat())
            case .item(let item):
                collection.append(item)
            case .none:
                if let value = optionalStyle() {
                    collection.append(.init(
                        name: key,
                        value: applyWhitespaceStyle(value)
                    ))
                }
            }
        }

        return .collection(collection)
    }

    fileprivate func decodeCollection(_ name: String, _ array: any Collection) -> QueryEncoded {
        var collection = QueryCollection(name) { $0 }

        var index = 0
        for item in array {

            switch encode(item, for: "\(index)") {
            case .collection(let valueCollection):
                collection.append(contentsOf: valueCollection.flat().map {
                    .init(
                        name: applyWhitespaceStyle(arrayStyle(index) + $0.name),
                        value: $0.value
                    )
                })
            case .item(let item):
                collection.append(.init(
                    name: applyWhitespaceStyle(arrayStyle(index) + item.name),
                    value: item.value
                ))
            case .none:
                if let value = optionalStyle() {
                    collection.append(.init(
                        name: applyWhitespaceStyle(arrayStyle(index)),
                        value: applyWhitespaceStyle(value)
                    ))
                }
            }

            index += 1
        }

        return .collection(collection)
    }

    fileprivate func decodeOptional(_ optionalValue: Any?, _ name: String) -> QueryEncoded {
        return optionalValue.map {
            encode($0, for: name)
        } ?? .none
    }

    fileprivate func decodeString(_ name: String, _ value: String) -> QueryEncoded {
        return .item(.init(
            name: name,
            value: applyWhitespaceStyle(value)
        ))
    }

    fileprivate func decodeAny<Value>(_ name: String, _ value: Value) -> QueryEncoded {
        return .item(.init(
            name: name,
            value: applyWhitespaceStyle("\(value)")
        ))
    }

    public func encode<Value>(_ value: Value, for name: String) -> QueryEncoded {
        let name = nameStyle(name)

        switch value {
        case let date as Date:
            return decodeDate(name, date)
        case let data as Data:
            return decodeData(name, data)
        case let flag as Bool:
            return decodeBool(name, flag)
        case let dictionary as [AnyHashable: Any]:
            return decodeDictionary(name, dictionary)
        case let array as any Collection:
            return decodeCollection(name, array)
        case let value as String:
            return decodeString(name, value)
        case let optionalValue as Optional<Any>:
            return decodeOptional(optionalValue, name)
        default:
            return decodeAny(name, value)
        }
    }
}

extension QueryStyle where Self == QueryFormatter {

    public static var `default`: QueryFormatter {
        .init()
    }

    public static func formatter(_ formatter: QueryFormatter) -> QueryFormatter {
        formatter
    }
}

struct QueryStyleEnvironmentKey: EnvironmentKey {
    static var defaultValue: QueryStyle = .default
}

extension EnvironmentValues {

    var queryStyle: QueryStyle {
        get { self[QueryStyleEnvironmentKey.self] }
        set { self[QueryStyleEnvironmentKey.self] = newValue }
    }
}

extension Property {

    public func queryStyle<Style: QueryStyle>(_ style: Style) -> some Property {
        environment(\.queryStyle, style)
    }
}
