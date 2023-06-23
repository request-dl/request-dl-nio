/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Set the `User-Agent` header of the request.

 If the `User-Agent` field is required in the request, the ``RequestDL/UserAgentHeader`` provides two
 ways to configure the header.

 To use the default value of RequestDL, simply use the empty initializer ``RequestDL/UserAgentHeader/init()``.
 Alternatively, you can specify your own value using the initializer ``RequestDL/UserAgentHeader/init(_:)``.

 ```swift
 UserAgentHeader("CustomAgent")
 ```

 > Important: Multiple specifications of ``RequestDL/UserAgentHeader`` are internally resolved by combining
 the values in the pattern `%@ %@`.
 */
public struct UserAgentHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let value: String

    // MARK: - Inits

    /**
     Initialize with a custom agent to be added to the headers.

     - Parameter userAgent: The custom agent value.
     */
    public init<S: StringProtocol>(_ userAgent: S) {
        self.value = String(userAgent)
    }

    /// Initialize the `User-Agent` with **APP\_NAME/APP\_VERSION SYS\_NAME/SYS\_VERSION** value.
    public init() {
        value = ProcessInfo.processInfo.userAgent
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<UserAgentHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: "User-Agent",
            value: property.value.trimmingCharacters(in: .whitespaces),
            strategy: inputs.environment.headerStrategy,
            separator: " "
        ))
    }
}
