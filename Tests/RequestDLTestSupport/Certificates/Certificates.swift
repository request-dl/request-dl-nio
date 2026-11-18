//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct Certificates {

    private let format: Internals.Certificate.Format

    init(_ format: Internals.Certificate.Format = .pem) {
        self.format = format
    }

    func server() -> CertificateResource {
        .init("server", format: format)
    }

    /// pass:password
    func client(password: Bool = false) -> CertificateResource {
        .init(
            password ? "client_password" : "client",
            format: format
        )
    }

    /// An EC (P-256) client certificate/key pair, as opposed to `client()`'s RSA one.
    func clientEC() -> CertificateResource {
        .init("client_ec", format: format)
    }
}
