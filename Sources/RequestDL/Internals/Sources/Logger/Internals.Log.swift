/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension Internals {

    struct Log: Sendable {

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
extension Internals.Log {

    static func unexpectedStateOrPhase<State: Sendable, Phase: Sendable>(
        state: State,
        phase: Phase,
        error: Error? = nil
    ) -> Internals.Log {
        Internals.Log(
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
extension Internals.Log {

    static func cantCreateCertificateOutsideSecureConnection() -> Internals.Log {
        Internals.Log(
            """
            It seems that you are attempting to create a Certificate \
            property outside of the allowed context.

            Please note that Certificates, TrustRoots, and AdditionalTrustRoots \
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
    ) -> Internals.Log {
        Internals.Log(
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
extension Internals.Log {

    static func accessingNeverBody<Property: Sendable>(
        _ property: Property
    ) -> Internals.Log {
        Internals.Log(
            """
            An unexpected attempt was made to access the property body.
            """,
            metadata: [String(describing: type(of: property)): .string(.init(describing: property))]
        )
    }

    static func unexpectedGraphPathway() -> Internals.Log {
        Internals.Log(
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

    static func environmentNilValue<KeyPath: Sendable>(_ keyPath: KeyPath) -> Internals.Log {
        Internals.Log(
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
extension Internals.Log {

    static func loweringCacheCapacityOnInitNotPermitted<Memory: Sendable, Disk: Sendable>(
        _ memoryCapacity: Memory,
        _ diskCapacity: Disk
    ) -> Internals.Log {
        Internals.Log(
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

extension Internals.Log {

    func preconditionFailure(
        file: StaticString = #fileID,
        function: String = #function,
        line: UInt = #line,
        logger: Logger? = nil
    ) -> Never {
        logMetadata(
            level: .error,
            logger: logger ?? RequestEnvironmentValues.current.logger
        )

        Internals.preconditionFailure(
            message().description,
            file: file,
            line: line
        )
    }
}

extension Internals.Log {

    func log(
        level: Logger.Level,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        logger: Logger?
    ) {
        if let logger {
            logger.log(
                level: level,
                message(),
                metadata: metadata?(),
                file: file,
                function: function,
                line: line
            )
        } else {
            var content = ["RequestDL.Log \(level)"]

            content.append(message().description)

            if let metadata {
                content.append(metadata().description)
            }

            content.append("-> \(file):\(line)")

            print(content.joined(separator: "\n\n"))
        }
    }

    fileprivate func logMetadata(
        level: Logger.Level,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        logger: Logger?
    ) {
        guard let metadata else {
            return
        }

        if let logger {
            logger.log(
                level: level,
                .init(stringLiteral: metadata().description),
                file: file,
                function: function,
                line: line
            )
        } else {
            print(
                """
                Crash Metadata Information
                
                \(metadata().description)
                
                -> \(file):\(line)
                """
            )
        }
    }
}
