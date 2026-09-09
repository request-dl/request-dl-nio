//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Security

extension Internals.RevocationPolicy {

    /// The `SecPolicyCreateRevocation` policy this case composes onto a `SecTrust`'s policy array,
    /// via `Internals.DarwinTrustEvaluation.prepare(_:skipsHostnameVerification:)`.
    var secPolicy: SecPolicy {
        // `SecPolicyCreateRevocation` is declared `__nullable` in the SDK header the way every
        // `SecPolicyCreate*` factory is, but never actually returns `NULL` for any combination of
        // its own documented flags -- there's no invalid combination among
        // `kSecRevocation*`'s five bits for it to reject.
        switch self {
        case .strict:
            // `kSecRevocationRequirePositiveResponse` is what turns `SecTrust`'s already-automatic,
            // best-effort revocation check into a hard requirement; `kSecRevocationUseAnyAvailableMethod`
            // lets the peer's own certificate pick OCSP or CRL rather than forcing one.
            return SecPolicyCreateRevocation(
                kSecRevocationUseAnyAvailableMethod | kSecRevocationRequirePositiveResponse
            )!
        case .disabled:
            return SecPolicyCreateRevocation(kSecRevocationNetworkAccessDisabled)!
        }
    }
}

#endif
