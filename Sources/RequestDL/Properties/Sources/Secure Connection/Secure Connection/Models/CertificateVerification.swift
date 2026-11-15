//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// An enumeration that represents different modes of certificate verification.
///
/// `CertificateVerification` provides options to specify how certificates should be verified in Swift.
public enum CertificateVerification: Sendable, Hashable {

    /// Indicates that all certificate verification is disabled.
    ///
    /// - Warning: This includes ``SPKIPinning`` under the SwiftNIO and URLSession executors, which never run the
    /// pin check once verification is off. Network.framework still does, so the same configuration can behave
    /// differently per executor; RequestDL logs a warning when the two are combined.
    case none

    /// Specifies that certificate validation will be performed against the trust store, but without verifying
    /// if the certificates are valid for the specified hostname.
    case noHostnameVerification

    /// Specifies that certificate validation will be performed against the trust store and includes verification
    /// against the hostname of the service being contacted
    case fullVerification

    // MARK: - Internal methods

    func build() -> Internals.CertificateVerification {
        switch self {
        case .none:
            return .none
        case .noHostnameVerification:
            return .noHostnameVerification
        case .fullVerification:
            return .fullVerification
        }
    }
}
