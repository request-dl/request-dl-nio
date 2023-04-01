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

    static func cantResolveCertificatesForServer() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            The required resources for building the certificate chain \
            or private key could not be found or accessed.
            """
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

// MARK: [Internals] - Task
extension Internals.Log.Message {

    static func emptyRequestBody() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Creating a RequestBody with an empty BodyContent is potentially \
            risky and may cause unexpected behavior.

            Please ensure that a valid content is provided to the RequestBody \
            to avoid any potential issues.

            If no content is intended for the RequestBody, please consider \
            using a different approach.
            """
        )
    }

    static func accessingAbstractContent() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            There was an attempt to access a variable for which access was not expected.
            """
        )
    }
}

// MARK: - Resolve
extension Internals.Log.Message {

    static func cantResolveBaseURLFromNodes<Node, Root>(
        _ node: Node,
        for root: Root.Type
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Failed to find the required BaseURL object in the context.
            """,
            parameters: [
                String(describing: root): node
            ]
        )
    }
}

// MARK: - Secure Connection
extension Internals.Log.Message {

    static func unexpectedCertificateSource<Source>(
        _ source: Source
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            """,
            parameters: [
                String(describing: type(of: source)): source
            ]
        )
    }
}

// MARK: - Property
extension Internals.Log.Message {

    static func accessingNeverBody<Property>(
        _ property: Property
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An unexpected attempt was made to access the property body.
            """,
            parameters: [String(describing: type(of: property)): property]
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
