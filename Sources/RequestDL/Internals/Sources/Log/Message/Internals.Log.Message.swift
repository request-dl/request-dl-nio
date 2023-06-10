/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// swiftlint:disable file_length
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
                String(describing: type(of: phase)): phase
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

    static func cantSerializeJSONData<Dictionary, Options>(
        _ dictionary: Dictionary,
        _ options: Options,
        _ error: Error
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An error occurred while trying to serialize JSON data: \(error.localizedDescription).
            """,
            parameters: [
                String(describing: type(of: error)): error,
                String(describing: type(of: options)): options,
                String(describing: type(of: dictionary)): dictionary
            ] as [String: Any]
        )
    }

    static func cantEncodeObject<Object>(
        _ object: Object,
        _ error: Error
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An error occurred while trying to encode the object to data: \(error.localizedDescription).
            """,
            parameters: [
                String(describing: type(of: error)): error,
                String(describing: type(of: object)): object
            ] as [String: Any]
        )
    }

    static func cantEncodeString<Object, Encoding>(
        _ object: Object,
        _ encoding: Encoding
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An error occurred while trying to encode the string to data.
            """,
            parameters: [
                String(describing: type(of: object)): object,
                String(describing: type(of: encoding)): encoding
            ] as [String: Any]
        )
    }

    static func accessingAbstractContent() -> Internals.Log.Message {
        Internals.Log.Message(
            """
            There was an attempt to access a variable for which access was not expected.
            """
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

// MARK: - BaseURL
extension Internals.Log.Message {

    static func invalidHost<URL>(_ url: URL) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Invalid host string: The protocol communication should \
            not be included.
            """,
            parameters: [
                String(describing: type(of: url)): url
            ]
        )
    }

    static func unexpectedHost<URL>(_ url: URL) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Unexpected format for host string: Could not extract the \
            host.
            """,
            parameters: [
                String(describing: type(of: url)): url
            ]
        )
    }
}

// MARK: - Payload

extension Internals.Log.Message {

    static func stringEncodingHasNoEffectInPayload<Encoding>(
        _ encoding: Encoding
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            Specifying the `using:` parameter with a value of \
            type `String.Encoding` has no impact or effect on \
            the payload encoding. This means that specifying a \
            specific string encoding, such as UTF-8 or ASCII, \
            does not affect how the payload is encoded.

            To use a different encoding, you should use the \
            `.charset(_:)` method on the payload structure. \
            It's important to note that only commonly used \
            encoding formats are available for selection.

            Make sure to choose the appropriate encoding method \
            based on the type of content you are dealing with.
            """,
            parameters: [
                String(describing: type(of: encoding)): encoding
            ]
        )
    }

    static func fileWillBeRawBytesContentType<URL>(
        _ url: URL
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            When sending a payload by providing only the URL, \
            the Content-Type header is automatically set to \
            `application/octet-stream`.

            To specify a different content type, you need to use \
            the `.init(url:contentType:)` initializer. This allows \
            you to explicitly define the content type for the \
            payload.
            """,
            parameters: [
                String(describing: type(of: url)): url
            ]
        )
    }
}

// MARK: - Tasks
extension Internals.Log.Message {

    static func timesShouldBeGreaterThanZero<Times>(
        _ times: Times
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            The 'times' parameter must be greater than 0.
            """,
            parameters: [
                String(describing: type(of: times)): times
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

// MARK: - Modifiers
extension Internals.Log.Message {

    static func missingStagesOfRequest<Content>(
        _ content: Content
    ) -> Internals.Log.Message {
        Internals.Log.Message(
            """
            An error occurred while attempting to iterate through an \
            asynchronous sequence representing the stages of a request.

            The absence of a complete request was detected, as the loop \
            terminated prematurely without encountering an upload or download \
            step.

            Please, open a bug report 🔎
            """,
            parameters: [
                String(describing: type(of: content)): content
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
// swiftlint:enable file_length
