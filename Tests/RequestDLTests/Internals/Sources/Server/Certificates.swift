/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Certificates {

    private let format: Certificate.Format

    public init(_ format: Certificate.Format = .pem) {
        self.format = format
    }

    public func server() -> CertificateResource {
        .init("server", in: .module, format: format)
    }

    /// pass:password
    public func client(password: Bool = false) -> CertificateResource {
        .init(
            password ? "client_password" : "client",
            in: .module,
            format: format
        )
    }
}
