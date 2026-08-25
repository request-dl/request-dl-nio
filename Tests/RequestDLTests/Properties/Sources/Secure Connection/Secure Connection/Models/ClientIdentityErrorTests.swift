//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import Security
import Testing

@testable import RequestDL

/// Covers `ClientIdentityError`'s own rewrap/description logic -- independent of the real
/// Keychain round-trip that actually triggers it (`RawTaskExecutorDispatchTests` covers that end
/// to end through the public `DataTask` API). Without this type, `RawTask.result()` would let
/// `Internals.RawBytesIdentityBuilder.Error`/`Internals.URLSessionIdentityPolicy.ConfigurationError`
/// -- both package-visible, unreachable by name outside this package -- leak straight to a public
/// `DataTask`/`UploadTask`/`DownloadTask` caller, and `error.localizedDescription` on either one
/// is Foundation's generic "The operation couldn't be completed" text, not the actionable message
/// their own `CustomStringConvertible.description` carries. These tests pin both the rewrap and
/// the `errorDescription`/`localizedDescription` fix in place.
struct ClientIdentityErrorTests {

    @Test
    func error_whenRewrappedFromConfigurationError_carriesMatchingReason() async throws {
        // Given
        let incomplete = Internals.URLSessionIdentityPolicy.ConfigurationError.incompleteClientIdentity
        let empty = Internals.URLSessionIdentityPolicy.ConfigurationError.emptyCertificateChain

        // When
        let incompleteError = ClientIdentityError(incomplete)
        let emptyError = ClientIdentityError(empty)

        // Then
        guard case .incompleteClientIdentity = incompleteError.reason else {
            Issue.record("Expected .incompleteClientIdentity, got \(incompleteError.reason)")
            return
        }
        guard case .emptyCertificateChain = emptyError.reason else {
            Issue.record("Expected .emptyCertificateChain, got \(emptyError.reason)")
            return
        }
    }

    @Test
    func error_whenRewrappedFromMissingEntitlement_carriesOperationAndReadsActionably() async throws {
        // Given
        let internalError = Internals.RawBytesIdentityBuilder.Error.missingKeychainSharingEntitlement(
            operation: "SecItemAdd(key)"
        )

        // When
        let error = ClientIdentityError(internalError)

        // Then
        guard case .missingKeychainSharingEntitlement(let operation) = error.reason else {
            Issue.record("Expected .missingKeychainSharingEntitlement, got \(error.reason)")
            return
        }
        #expect(operation == "SecItemAdd(key)")
        #expect(error.description.contains("Keychain Sharing"))
        #expect(error.description.contains("Signing & Capabilities"))
        #expect(error.description.contains("Using-a-Client-Certificate-with-URLSession.md"))
    }

    /// The exact gap this type exists to close: `.localizedDescription` -- what most catch sites
    /// actually print/display -- must carry the same actionable text `.description` does, not
    /// Foundation's generic NSError fallback. Confirmed failing before `LocalizedError`
    /// conformance was added (see the phase's own investigation), not assumed.
    @Test
    func error_whenAccessedViaLocalizedDescription_readsTheSameActionableTextAsDescription() async throws {
        // Given
        let internalError = Internals.RawBytesIdentityBuilder.Error.missingKeychainSharingEntitlement(
            operation: "SecItemAdd(key)"
        )
        let error = ClientIdentityError(internalError)

        // When
        let localized = (error as any Error).localizedDescription

        // Then
        #expect(localized == error.description)
        #expect(localized.contains("Keychain Sharing"))
    }

    @Test
    func error_whenRewrappedFromKeychainOperationFailed_describesTheOSStatus() async throws {
        // Given
        let internalError = Internals.RawBytesIdentityBuilder.Error.keychainOperationFailed(
            errSecItemNotFound,
            operation: "SecItemCopyMatching(identity)"
        )

        // When
        let error = ClientIdentityError(internalError)

        // Then
        guard case .keychainOperationFailed(let operation, let status) = error.reason else {
            Issue.record("Expected .keychainOperationFailed, got \(error.reason)")
            return
        }
        #expect(operation == "SecItemCopyMatching(identity)")
        #expect(status == errSecItemNotFound)
        #expect(error.description.contains("SecItemCopyMatching(identity)"))
        #expect(error.description.contains("\(errSecItemNotFound)"))
        // This bucket must not claim a missing entitlement -- it can be a genuinely different,
        // still-unresolved issue on non-sandboxed macOS (see <doc:Using-a-Client-Certificate-with-URLSession>'s
        // "Platforms" section), and telling someone to add a capability that won't fix it would be
        // actively misleading.
        #expect(!error.description.contains("Keychain Sharing"))
    }

    @Test(
        arguments: [
            Internals.RawBytesIdentityBuilder.Error.invalidCertificateData,
            .unsupportedKeyFormat("-----BEGIN PRIVATE KEY-----"),
            .secKeyCreationFailed("bad key"),
            .keychainOperationFailed(errSecDuplicateItem, operation: "SecItemAdd(certificate)"),
            .missingKeychainSharingEntitlement(operation: "SecItemAdd(key)"),
            .identityLookupReturnedWrongType,
        ]
    )
    func error_whenEveryInternalCaseRewrapped_hasNonEmptyDescription(
        _ internalError: Internals.RawBytesIdentityBuilder.Error
    ) async throws {
        // When
        let description = ClientIdentityError(internalError).description

        // Then
        #expect(!description.isEmpty)
    }
}

#endif
