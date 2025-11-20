/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension Logger {

    struct Payload: Sendable {

        let message: @Sendable () -> Logger.Message
        let metadata: (@Sendable () -> Logger.Metadata)?

        init(_ message: @autoclosure @escaping @Sendable () -> Logger.Message, metadata: @autoclosure @escaping @Sendable () -> Logger.Metadata) {
            self.message = message
            self.metadata = metadata
        }

        init(_ message: @autoclosure @escaping @Sendable () -> Logger.Message) {
            self.message = message
            self.metadata = nil
        }
    }
}

// MARK: [Internals] - Session
extension Logger.Payload {

    static func unexpectedStateOrPhase<State: Sendable, Phase: Sendable>(
        state: State,
        phase: Phase,
        error: Error? = nil
    ) -> Logger.Payload {
        Logger.Payload(
            """
            An invalid state or phase has been detected, which could \
            cause unexpected behavior within the application.

            If this was not an intentional change, please report this \
            issue by opening a bug report 🔎.
            """,
            metadata: [
                String(describing: type(of: state)): .string(String(describing: state)),
                String(describing: type(of: phase)): .string(String(describing: phase))
            ].merging(error.map {[
                String(describing: type(of: $0)): .string(String(describing: $0))
            ]} ?? [:], uniquingKeysWith: { lhs, _ in lhs })
        )
    }
}

// MARK: - Secure Connection
extension Logger.Payload {

    static func cantCreateCertificateOutsideSecureConnection() -> Logger.Payload {
        Logger.Payload(
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

    static func cantOpenCertificateFile<Resource: Sendable, Bundle: Sendable>(
        _ resource: Resource,
        _ bundle: Bundle
    ) -> Logger.Payload {
        Logger.Payload(
            """
            An error occurred while trying to access an invalid file path.
            """,
            metadata: [
                String(describing: type(of: resource)): .string(.init(describing: resource)),
                String(describing: type(of: bundle)): .string(.init(describing: bundle))
            ]
        )
    }
}

// MARK: - Property
extension Logger.Payload {

    static func accessingNeverBody<Property: Sendable>(
        _ property: Property
    ) -> Logger.Payload {
        Logger.Payload(
            """
            An unexpected attempt was made to access the property body.
            """,
            metadata: [String(describing: type(of: property)): .string(.init(reflecting: property))]
        )
    }

    static func unexpectedGraphPathway() -> Logger.Payload {
        Logger.Payload(
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

    static func environmentNilValue<KeyPath: Sendable>(_ keyPath: KeyPath) -> Logger.Payload {
        Logger.Payload(
            """
            This can occur if the property wrapper's key path does not \
            exist in the current environment, or if the environment has \
            not been properly set up.

            Please ensure that the environment is correctly configured \
            and that the key path provided to the property wrapper is \
            valid.
            """,
            metadata: [
                String(describing: type(of: keyPath)): .string(.init(describing: keyPath))
            ]
        )
    }
}

// MARK: - Cache
extension Logger.Payload {

    static func loweringCacheCapacityOnInitNotPermitted<Memory: Sendable, Disk: Sendable>(
        _ memoryCapacity: Memory,
        _ diskCapacity: Disk
    ) -> Logger.Payload {
        Logger.Payload(
            """
            Cannot decrease the capacity of the disk or memory during \
            DataCache initialization.

            To accomplish this, you must directly access the DataCache \
            object.
            """,
            metadata: [
                "memoryCapacity": .string(.init(describing: memoryCapacity)),
                "diskCapacity": .string(.init(describing: diskCapacity))
            ]
        )
    }
}

extension Logger {

    fileprivate func debugParameters(
        metadata: () -> Logger.Metadata,
        file: StaticString,
        function: String,
        line: UInt
    ) {
        func debugDescription() -> String {
            metadata().reduce([String]()) {
                $0 + ["\($1.key) = \(String(describing: $1.value))"]
            }
            .joined(separator: "\n")
        }

        debug(
            .init(stringLiteral: debugDescription()),
            file: file.withUTF8Buffer {
                String(decoding: $0, as: UTF8.self)
            },
            function: function,
            line: line
        )
    }

    func info(
        _ payload: Logger.Payload,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        info(
            payload.message(),
            metadata: payload.metadata?(),
            file: file,
            function: function,
            line: line
        )
    }
}

extension Internals {

    static func preconditionFailure(
        _ payload: Logger.Payload,
        file: StaticString = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Never {
        #if DEBUG
        if let metadata = payload.metadata {
            Logger.current.debugParameters(
                metadata: metadata,
                file: file,
                function: function,
                line: line
            )
        }
        #endif

        preconditionFailure(
            payload.message().description,
            file: file,
            line: line
        )
    }
}
