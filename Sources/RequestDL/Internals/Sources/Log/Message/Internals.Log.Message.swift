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
            parameters: [String: Any] = [:]
        ) {
            self.message = message
            self.parameters = parameters
        }
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
                String(describing: type(of: phase)): phase
            ].merging(error.map {[
                String(describing: type(of: $0)): $0
            ]} ?? [:], uniquingKeysWith: { lhs, _ in lhs })
        )
    }
}

// MARK: - Secure Connection
extension Internals.Log.Message {

    static func cantCreateCertificateOutsideSecureConnection() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            It seems that you are attempting to create a Certificate \
            property outside of the allowed context.

            Please note that Certificates, Trusts, and AdditionalTrusts \
            are the only valid contexts in which you can create a \
            Certificate property.

            Please ensure that you are creating your Certificate property \
            within one of these contexts to avoid encountering this error.
            """
        )
    }

    static func cantOpenCertificateFile<Resource, Bundle>(
        _ resource: Resource,
        _ bundle: Bundle
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An error occurred while trying to access an invalid file path.
            """,
            parameters: [
                String(describing: type(of: resource)): resource,
                String(describing: type(of: bundle)): bundle
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

    static func unexpectedGraphPathway() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            You are attempting to modify the graph pathway, which is not \
            allowed. Please do not call the _makeProperty function or \
            attempt to change the default implementation, as this can lead \
            to errors.

            If you require a different implementation, please create a new \
            function or modify an existing one that does not affect the \
            graph pathway.
            """
        )
    }

    static func environmentNilValue<KeyPath>(_ keyPath: KeyPath) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            This can occur if the property wrapper's key path does not \
            exist in the current environment, or if the environment has \
            not been properly set up.

            Please ensure that the environment is correctly configured \
            and that the key path provided to the property wrapper is \
            valid.
            """,
            parameters: [
                String(describing: type(of: keyPath)): keyPath
            ]
        )
    }
}

// MARK: - Cache
extension Internals.Log.Message {

    static func loweringCacheCapacityOnInitNotPermitted<Memory, Disk>(
        _ memoryCapacity: Memory,
        _ diskCapacity: Disk
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Cannot decrease the capacity of the disk or memory during \
            DataCache initialization.

            To accomplish this, you must directly access the DataCache \
            object.
            """,
            parameters: [
                "memoryCapacity": memoryCapacity,
                "diskCapacity": diskCapacity
            ]
        )
    }
}

extension Internals.Log {

    private static func debugParameters(
        parameters: [String: Any],
        line: UInt,
        file: StaticString
    ) {
        debug(
            parameters
                .reduce([String]()) {
                    $0 + ["\($1.key) = \(String(describing: $1.value))"]
                }
                .joined(separator: "\n"),
            separator: "",
            line: line,
            file: file
        )
    }

    static func warning(
        _ message: Message,
        line: UInt = #line,
        file: StaticString = #file
    ) {
        #if DEBUG
        if !message.parameters.isEmpty {
            debugParameters(
                parameters: message.parameters,
                line: line,
                file: file
            )
        }
        #endif

        warning(
            message.message,
            separator: "",
            line: line,
            file: file
        )
    }

    static func failure(
        _ message: Message,
        line: UInt = #line,
        file: StaticString = #file
    ) -> Never {
        #if DEBUG
        if !message.parameters.isEmpty {
            debugParameters(
                parameters: message.parameters,
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
