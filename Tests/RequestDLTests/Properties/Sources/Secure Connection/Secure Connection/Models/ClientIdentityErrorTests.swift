//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import Security
import Testing

@testable import RequestDL

/// Covers `ClientIdentityError`'s own rewrap/description logic, independent of the identity build
/// that actually triggers it (`RawTaskExecutorDispatchTests` covers that end to end through the
/// public `DataTask` API).
///
/// Without this type, `RawTask.result()` would let
/// `Internals.RawBytesIdentityBuilder.Error`/`Internals.URLSessionIdentityPolicy.ConfigurationError`
/// (both package-visible, unreachable by name outside this package) leak straight to a public
/// `DataTask`/`UploadTask`/`DownloadTask` caller, and `error.localizedDescription` on either one
/// is Foundation's generic "The operation couldn't be completed" text, not the actionable message
/// their own `CustomStringConvertible.description` carries.
///
/// These tests pin both the rewrap and the `errorDescription`/`localizedDescription` fix in place.
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

    /// The Keychain reasons are deprecated and kept so existing `switch` statements over `Reason`
    /// keep compiling, but nothing throws them any more. They still describe themselves without
    /// trapping, and the entitlement one no longer tells anyone to add a capability that is not
    /// needed.
    ///
    /// Deprecated itself, so that naming the deprecated cases here raises no warning.
    @available(*, deprecated)
    @Test
    func reason_whenALegacyKeychainCase_stillDescribesItselfAndAsksForNoCapability() async throws {
        // Given
        let reasons: [ClientIdentityError.Reason] = [
            .missingKeychainSharingEntitlement(operation: "SecItemAdd(key)"),
            .keychainOperationFailed(operation: "SecItemCopyMatching(identity)", status: errSecItemNotFound),
            .identityLookupReturnedWrongType,
        ]

        for reason in reasons {
            // Then
            #expect(!reason.description.isEmpty)
            #expect(!reason.description.contains("Signing & Capabilities"))
        }

        #expect(reasons[0].description.contains("no longer thrown"))
        #expect(reasons[1].description.contains("SecItemCopyMatching(identity)"))
        #expect(reasons[1].description.contains("\(errSecItemNotFound)"))
        #expect(reasons[2].description.contains("unexpected type"))
    }

    /// The exact gap this type exists to close: `.localizedDescription` (what most catch sites
    /// actually print/display) must carry the same actionable text `.description` does, not
    /// Foundation's generic NSError fallback.
    @Test
    func error_whenAccessedViaLocalizedDescription_readsTheSameActionableTextAsDescription() async throws {
        // Given
        let error = ClientIdentityError(Internals.RawBytesIdentityBuilder.Error.invalidCertificateData)

        // When
        let localized = (error as any Error).localizedDescription

        // Then
        #expect(localized == error.description)
        #expect(localized.contains("could not be parsed as a certificate"))
    }

    @Test(
        arguments: [
            Internals.RawBytesIdentityBuilder.Error.invalidCertificateData,
            .unsupportedKeyFormat("-----BEGIN PRIVATE KEY-----"),
            .secKeyCreationFailed("bad key"),
            .privateKeyDoesNotMatchCertificate,
            .unsupportedCertificatePublicKey,
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

    @Test
    func error_whenThePrivateKeyIsNotTheCertificates_saysSo() async throws {
        // When
        let error = ClientIdentityError(Internals.RawBytesIdentityBuilder.Error.privateKeyDoesNotMatchCertificate)

        // Then
        guard case .keyCreationFailed(let message) = error.reason else {
            Issue.record("Expected .keyCreationFailed, got \(error.reason)")
            return
        }
        #expect(message == "it is not the private key of the configured certificate")
        #expect(error.description.contains("not the private key of the configured certificate"))
        #expect(!error.description.contains("Keychain Sharing"))
    }
}

#endif
