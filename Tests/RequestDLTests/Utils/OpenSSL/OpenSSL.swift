//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if os(macOS)
struct OpenSSL {

    private let name: String
    private let options: [OpenSSLOption]

    init(_ name: String, with options: [OpenSSLOption] = []) {
        self.name = name
        self.options = options
    }
}

extension OpenSSL {

    func certificate() throws -> OpenSSLCertificate {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL_OpenSSL.\(UUID())")

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let certificate = outputURL.appending(name, extension: "crt")
        let privateKey = outputURL.appending(name, extension: "key")

        try Process.zsh(
            """
            openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
                -keyout \(privateKey.normalizePath) \
                -out \(certificate.normalizePath) \
                -subj "/CN=localhost"
            """
        ).waitUntilExit()

        var personalFileExchangeURL: URL?

        for option in options {
            switch option {
            case .pfx(let password):
                let pfxURL = outputURL.appending(name, extension: "pfx")

                try Process.zsh(
                    """
                    openssl pkcs12 -export \
                        -in \(certificate.normalizePath) \
                        -inkey \(privateKey.normalizePath) \
                        -out \(pfxURL.normalizePath) \
                        -passout pass:\(password)
                    """
                ).waitUntilExit()

                personalFileExchangeURL = pfxURL
            }
        }

        return .init(
            certificateURL: certificate,
            privateKeyURL: privateKey,
            personalFileExchangeURL: personalFileExchangeURL
        )
    }
}
#endif
