/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Certificates {

    private let format: CertificateFormat

    public init(_ format: CertificateFormat = .pem) {
        self.format = format
    }

    public func server() -> CertificateResouce {
        .init("server", in: .module, format: format)
    }

    public func client(password: Bool = false) -> CertificateResouce {
        .init(
            password ? "client_password" : "client",
            in: .module,
            format: format
        )
    }
}
