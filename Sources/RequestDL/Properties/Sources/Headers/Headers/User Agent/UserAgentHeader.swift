/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Set the `User-Agent` header of the request.

 The default value for the `User-Agent` in RequestDL is "APP\_NAME/APP\_VERSION SYS\_NAME/SYS\_VERSION".
 If you want to add an extra parameter, you can use the ``RequestDL/UserAgentHeader``. You can also completely
 override the `User-Agent` values using ``RequestDL/Property/headerStrategy(_:)``.

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

     - Parameter userAgent: The custom agent to be added.
     */
    public init<S: StringProtocol>(_ userAgent: S) {
        self.value = String(userAgent)
    }

    /// Initialize the `User-Agent` with a default value
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
            appendingSeparator: " "
        ))
    }
}
