//
//  File.swift
//  
//
//  Created by Brenno on 28/03/23.
//

import Foundation

public enum Log {

    public static func debug(
        _ items: Any...,
        separator: String = " ",
        line: UInt = #line,
        file: StaticString = #file
    ) {
        _ = log(
            items,
            level: .debug,
            separator: separator,
            line: line,
            file: file
        )
    }

    public static func warning(
        _ items: Any...,
        separator: String = " ",
        line: UInt = #line,
        file: StaticString = #file
    ) {
        _ = log(
            items,
            level: .warning,
            separator: separator,
            line: line,
            file: file
        )
    }

    public static func failure(
        _ items: Any...,
        separator: String = " ",
        line: UInt = #line,
        file: StaticString = #file
    ) -> Never {
        log(
            items,
            level: .failure,
            separator: separator,
            line: line,
            file: file
        ).unsafelyUnwrapped
    }
}

extension Log {

    fileprivate static func log(
        _ items: Any...,
        level: Level,
        separator: String,
        line: UInt,
        file: StaticString
    ) -> Never? {
        let content = items
            .map { "\($0)" }
            .joined(separator: separator)

        let message = """
        RequestDL.Log \(level.rawValue)

        \(content)

        -> \(file):\(line)
        """

        switch level {
        case .debug, .warning:
            SwiftOverride.print(message)
            return nil
        case .failure:
            SwiftOverride.fatalError(message, file: file, line: line)
        }
    }
}

extension Log {

    fileprivate enum Level {
        case debug
        case warning
        case failure
    }
}

extension Log.Level {

    var rawValue: String {
        switch self {
        case .debug:
            return "💙 DEBUG"
        case .warning:
            return "⚠️ WARNING"
        case .failure:
            return "💔 FAILURE"
        }
    }
}
