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
}
