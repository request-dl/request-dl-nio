/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A SHA-256 hash of a SubjectPublicKeyInfo (SPKI) structure, Base64-encoded.
///
/// This type guarantees:
/// - Valid Base64 encoding (validated on first access)
/// - Exactly 32 bytes when decoded (SHA-256 length)
/// - No line breaks or whitespace (standard cryptographic Base64)
///
/// - Note: Always use Base64 format matching OpenSSL output:
///   ```
///   openssl dgst -sha256 -binary | openssl base64 -A
///   ```
public struct SPKIHash: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: SPKIHashSource

    // MARK: - Inits

    /// Creates an SPKI hash from a Base64-encoded SHA-256 string.
    ///
    /// - Parameter base64Encoded: A Base64 string representing SHA-256 hash data.
    ///   Validation occurs when `base64EncodedString` is accessed.
    public init<S: StringProtocol>(_ base64Encoded: S) {
        self.source = .base64String(String(base64Encoded))
    }

    /// Creates an SPKI hash from raw SHA-256 hash data.
    ///
    /// - Parameter  Raw SHA-256 hash data.
    ///   Validation occurs when `base64EncodedString` is accessed.
    public init(data: Data) {
        self.source = .rawData(data)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SPKIHash>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            SPKIHashNode(
                anchor: inputs.environment.spkiHashAnchor,
                source: property.source
            )
        )
    }
}
