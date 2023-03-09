/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

#if os(macOS)
struct OpenSSLServer {

    private let certificate: OpenSSLCertificate

    private let clientAuthentication: OpenSSLCertificate?

    private let output: String

    init(_ output: String, certificate: OpenSSLCertificate) {
        self.output = output
        self.certificate = certificate
        self.clientAuthentication = nil
    }

    init(
        _ output: String,
        certificate: OpenSSLCertificate,
        clientAuthentication: OpenSSLCertificate
    ) {
        self.output = output
        self.certificate = certificate
        self.clientAuthentication = clientAuthentication
    }
}

extension OpenSSLServer {

    func start(_ session: () async throws -> Void) async throws {
        let process = try Process.zsh(
            """
            echo -n "\(output)" > index
            \(command)
            """
        )

        defer { process.interrupt() }

        FatalError.replace { [weak process] in
            process?.interrupt()
            FatalError.restoreFatalError()
            Swift.fatalError($0, file: $1, line: $2)
        }

        try await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
        try await session()
    }
}

extension OpenSSLServer {

    fileprivate var command: String {
        var commands = ["openssl s_server -accept 8080"]

        if let clientPKCS12URL = clientAuthentication?.pkcs12URL, let password = clientAuthentication?.pkcs12Password {
            commands.append(
                """
                -CAfile \(clientPKCS12URL.normalizePath) \
                -pass pass:\(password) \
                -Verify 2
                """
            )
        }

        commands.append(
            """
            -cert \(certificate.certificateURL.normalizePath) \
            -key \(certificate.privateKeyURL.normalizePath) \
            -status_verbose \
            -debug \
            -WWW
            """
        )

        return commands.joined(separator: " ")
    }
}
#endif
