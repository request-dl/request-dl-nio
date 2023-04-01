/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.Log {

    struct Message {

        fileprivate let message: String
        fileprivate let parameters: [String: Any]

        fileprivate init(
            _ message: String,
            parameters: [String : Any] = [:]
        ) {
            self.message = message
            self.parameters = parameters
        }
    }
}

// MARK: [Internals] - Secure Connection
extension Internals.Log.Message {

    static func expectingCertificatesCase<T>(
        _ property: T
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            """,
            parameters: [
                String(describing: type(of: property)): property
            ]
        )
    }
}

// MARK: [Internals] - Session
extension Internals.Log.Message {

    static func unexpectedStateOrPhase<State, Phase>(
        state: State,
        phase: Phase,
        error: Error? = nil
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An invalid state or phase has been detected, which could \
            cause unexpected behavior within the application.

            If this was not an intentional change, please report this \
            issue by opening a bug report 🔎.
            """,
            parameters: [
                String(describing: type(of: state)): state,
                String(describing: type(of: phase)): phase,
            ].merging(error.map {[
                String(describing: type(of: $0)): $0
            ]} ?? [:], uniquingKeysWith: { lhs, _ in lhs })
        )
    }
}

extension Internals.Log {

    static func failure(
        _ message: Message,
        line: UInt = #line,
        file: StaticString = #file
    ) -> Never {
        #if DEBUG
        if !message.parameters.isEmpty {
            let message = message.parameters
                .reduce([String]()) {
                    $0 + ["\($1.key) = \(String(describing: $1.value))"]
                }
                .joined(separator: "\n")

            debug(
                message,
                separator: "",
                line: line,
                file: file
            )
        }
        #endif

        failure(
            message.message,
            separator: "",
            line: line,
            file: file
        )
    }
}
