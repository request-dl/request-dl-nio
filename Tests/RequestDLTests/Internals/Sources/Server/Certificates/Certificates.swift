/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

struct Certificates {

    private let format: Internals.Certificate.Format

    init(_ format: Internals.Certificate.Format = .pem) {
        self.format = format
    }

    func server() -> CertificateResource {
        .init("server", in: .module, format: format)
    }

    /// pass:password
    func client(password: Bool = false) -> CertificateResource {
        .init(
            password ? "client_password" : "client",
            in: .module,
            format: format
        )
    }
}
