//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

extension Internals {

    package struct Log: Sendable {

        package let message: @Sendable () -> Logger.Message
        package let metadata: (@Sendable () -> Logger.Metadata)?

        package init(
            _ message: @autoclosure @escaping @Sendable () -> Logger.Message,
            metadata: @autoclosure @escaping @Sendable () -> Logger.Metadata
        ) {
            self.message = message
            self.metadata = metadata
        }

        package init(_ message: @autoclosure @escaping @Sendable () -> Logger.Message) {
            self.message = message
            self.metadata = nil
        }
    }
}

// MARK: [Internals] - Session
extension Internals.Log {

    package static func unexpectedStateOrPhase<State: Sendable, Phase: Sendable>(
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
                String(describing: type(of: phase)): .string(String(describing: phase)),
            ].merging(
                error.map {
                    [
                        String(describing: type(of: $0)): .string(String(describing: $0))
                    ]
                } ?? [:],
                uniquingKeysWith: { lhs, _ in lhs }
            )
        )
    }
}

// MARK: - Secure Connection
extension Internals.Log {

    package static func cantCreateCertificateOutsideSecureConnection() -> Internals.Log {
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

    package static func pinsIgnoredWithoutCertificateVerification() -> Internals.Log {
        Internals.Log(
            """
            SPKIPinning is configured together with .verification(.none), \
            which turns certificate verification off entirely.

            The SwiftNIO (.nio) and URLSession (.urlSession) executors never \
            run the pin check when verification is off, so the pins are NOT \
            enforced there. Network.framework (.nioTransportServices) still \
            enforces them, so the same request can be accepted or rejected \
            depending on the executor.

            Remove .verification(.none) to have the pins enforced \
            everywhere, or remove SPKIPinning if you really want no \
            verification.
            """
        )
    }

    package static func cantOpenCertificateFile<Resource: Sendable, Bundle: Sendable>(
        _ resource: Resource,
        _ bundle: Bundle
    ) -> Internals.Log {
        Internals.Log(
            """
            Couldn't find \(String(describing: resource)) in the given bundle.

            RequestDL looked for a resource matching that name (and, if it contains "/", inside \
            that subdirectory) among the bundle's resources and found nothing. This usually \
            means the file isn't part of the bundle at all — check that it's added to the \
            target's "Copy Bundle Resources" build phase — or that the name or extension passed \
            here doesn't match the file on disk.
            """,
            metadata: [
                String(describing: type(of: resource)): .string(.init(describing: resource)),
                String(describing: type(of: bundle)): .string(.init(describing: bundle)),
            ]
        )
    }
}

// MARK: - Property
extension Internals.Log {

    package static func accessingNeverBody<Property: Sendable>(
        _ property: Property
    ) -> Internals.Log {
        Internals.Log(
            """
            An unexpected attempt was made to access the property body.
            """,
            metadata: [String(describing: type(of: property)): .string(.init(describing: property))]
        )
    }

    package static func unexpectedGraphPathway() -> Internals.Log {
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
}

// MARK: - Proxy
extension Internals.Log {

    /// A request went direct because the PAC script that decides its proxy could not be asked.
    ///
    /// That is the choice that can send traffic around a proxy a network requires, so it is not
    /// left silent. Only the origin and path of the script are reported: its query and any
    /// credentials in it stay out of the log.
    package static func proxyAutoConfigurationFailedWentDirect(
        scriptURL: URL,
        failure: Internals.PACEvaluationFailure
    ) -> Internals.Log {
        var components = URLComponents(url: scriptURL, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil

        let script = components?.string ?? "?"
        let reason: String

        switch failure.reason {
        case .timedOut:
            reason = "timed out"

        case .failed:
            reason = "failed"
        }

        return Internals.Log(
            """
            The proxy auto-configuration (PAC) script could not be evaluated, so the request \
            was sent directly, around any proxy the script would have chosen.

            To fail the request instead, declare SystemProxy(onPACFailure: .fail); to use the \
            last answer the script gave, SystemProxy(onPACFailure: .lastKnown(orElse: .direct)).
            """,
            metadata: [
                "script": .string(script),
                "reason": .string(reason),
                "details": .string(failure.details ?? ""),
            ]
        )
    }
}

extension Internals.Log {

    package static func systemProxySOCKSCredentialsUndecodable() -> Internals.Log {
        let reason = "the user name or the password is not valid percent-encoded text"

        return Internals.Log(
            """
            The user name and password of the system's SOCKS proxy were ignored, because \(reason) \
            (a % that is not followed by two hex digits, or encoded bytes that are not UTF-8). \
            The request goes to the proxy without credentials, which fails if the proxy requires \
            them. Fix the encoding of the proxy URL, or declare \
            Proxy(host:port:connection:authorization:).
            """,
            metadata: ["reason": .string(reason)]
        )
    }

    /// The credentials of a SOCKS proxy that the system settings or the environment named could
    /// not be sent, so the proxy is used without them. Only why is reported, never the credentials.
    package static func systemProxySOCKSCredentialsIgnored(
        mismatch: Internals.Proxy.Authorization.Mismatch
    ) -> Internals.Log {
        let reason: String

        switch mismatch {
        case .socksUsernameLength(let count) where count == 0:
            reason = "the user name is empty"
        case .socksUsernameLength:
            reason = "the user name is longer than 255 bytes"
        case .socksPasswordLength:
            reason = "the password is longer than 255 bytes"
        case .socksCredentialContainsNUL:
            reason = "the user name or the password has a NUL character"
        case .httpShapeOnSOCKSProxy, .socksShapeOnHTTPProxy:
            reason = "they are not a user name and a password"
        }

        return Internals.Log(
            """
            The user name and password of the system's SOCKS proxy were ignored, because \(reason) \
            (SOCKS5 takes a user name of 1 to 255 bytes and a password of 0 to 255). The request \
            goes to the proxy without credentials, which fails if the proxy requires them. To \
            authenticate, declare Proxy(host:port:connection:authorization:).
            """,
            metadata: ["reason": .string(reason)]
        )
    }

    /// A request used the last answer a PAC script gave, because the script could not be asked now.
    ///
    /// The answer can be out of date, which is why it is reported. Only the origin and path of the
    /// script are, as in ``proxyAutoConfigurationFailedWentDirect(scriptURL:failure:)``.
    package static func proxyAutoConfigurationFailedUsedLastAnswer(
        scriptURL: URL,
        failure: Internals.PACEvaluationFailure,
        ageNanoseconds: UInt64
    ) -> Internals.Log {
        var components = URLComponents(url: scriptURL, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil

        let script = components?.string ?? "?"
        let seconds = ageNanoseconds / 1_000_000_000

        let reason: String

        switch failure.reason {
        case .timedOut:
            reason = "timed out"

        case .failed:
            reason = "failed"
        }

        return Internals.Log(
            """
            The proxy auto-configuration (PAC) script could not be evaluated, so the request \
            used the last answer the script gave, which may be out of date.
            """,
            metadata: [
                "script": .string(script),
                "reason": .string(reason),
                "details": .string(failure.details ?? ""),
                "answerAgeSeconds": .string(String(seconds)),
            ]
        )
    }
}

// MARK: - Cache
extension Internals.Log {

    package static func loweringCacheCapacityOnInitNotPermitted<Memory: Sendable, Disk: Sendable>(
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
                "diskCapacity": .string(.init(describing: diskCapacity)),
            ]
        )
    }
}

extension Internals.Log {

    package func assertionFailure(
        file: StaticString = #fileID,
        function: String = #function,
        line: UInt = #line,
        logger: Logger? = nil
    ) {
        logMetadata(
            level: .error,
            logger: logger
        )

        Internals.assertionFailure(
            message().description,
            file: file,
            line: line
        )
    }

    package func preconditionFailure(
        file: StaticString = #fileID,
        function: String = #function,
        line: UInt = #line,
        logger: Logger? = nil
    ) -> Never {
        logMetadata(
            level: .error,
            logger: logger
        )

        Internals.preconditionFailure(
            message().description,
            file: file,
            line: line
        )
    }
}

extension Internals.Log {

    package func log(
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
