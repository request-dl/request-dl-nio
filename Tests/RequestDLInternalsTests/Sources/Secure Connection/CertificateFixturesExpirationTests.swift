//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import typealias Foundation.TimeInterval
#endif

/// Confirms the self-signed TLS fixtures under `Tests/RequestDLTests/Resources/` haven't expired.
///
/// Not hypothetical: the originals were issued for 30 years with no Extended Key Usage or SAN
/// (see the git history of `Tests/RequestDLTests/Resources/SSL.md`), which
/// `SecTrustEvaluateWithError` -- the URLSession executor's certificate validation -- rejects
/// outright even when the certificate is explicitly anchored as trusted. See
/// `URLSESSION_TASK.md`, Phase 5e. The replacements `.scripts/generate-test-certificates.sh`
/// produces are deliberately short-lived (under Apple's enforced validity cap), which is exactly
/// why this check exists: it turns a stale fixture into one immediate, actionable failure here,
/// instead of a confusing TLS handshake error discovered later in an unrelated test.
struct CertificateFixturesExpirationTests {

    @Test
    func certificates_areNotExpired() throws {
        let fixtures: [(name: String, resource: CertificateResource)] = [
            ("server", Certificates().server()),
            ("client", Certificates().client()),
            ("client_password", Certificates().client(password: true)),
        ]

        for (name, resource) in fixtures {
            let certificate = try NIOSSLCertificate.fromPEMFile(
                resource.certificateURL.absolutePath(percentEncoded: false)
            ).first

            guard let certificate else {
                Issue.record("Could not load the \"\(name)\" test TLS certificate to check its expiration.")
                continue
            }

            let expiresAt = Date(timeIntervalSince1970: TimeInterval(certificate.notValidAfter))

            guard expiresAt > Date() else {
                Issue.record(
                    """
                    The "\(name)" test TLS certificate (\(resource.certificateURL.lastPathComponent)) \
                    expired on \(expiresAt). Regenerate the test TLS fixtures by running \
                    .scripts/generate-test-certificates.sh from the repository root, then commit the \
                    result.
                    """
                )
                continue
            }
        }
    }
}
