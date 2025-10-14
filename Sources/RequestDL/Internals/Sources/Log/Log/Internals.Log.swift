/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    enum Log {}
}

extension Internals.Log {

    static func debug(
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

    static func warning(
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

    static func failure(
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

extension Internals.Log {

    fileprivate static func log(
        _ items: [Any],
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
            Internals.Override.print(message)
            return nil
        case .failure:
            Internals.Override.fatalError(message, file: file, line: line)
        }
    }
}

extension Internals.Log {

    fileprivate enum Level {
        case debug
        case warning
        case failure
    }
}

extension Internals.Log.Level {

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
