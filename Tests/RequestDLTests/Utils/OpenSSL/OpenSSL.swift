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

        let privateKey = outputURL.appending(name, extension: "key")
        try generatePrivateKey(privateKey)

        let selfSignedCertificateRequest = outputURL.appending(name, extension: "crs")
        try generateSelfSignedCertificateRequest(selfSignedCertificateRequest, privateKey: privateKey)

        let certificate = outputURL.appending(name, extension: "pem")

        try generateCertificate(certificate, request: selfSignedCertificateRequest, privateKey: privateKey)

        var personalFileExchangeURL: URL?
        var certificateDEREncodedURL: URL?

        for option in options {
            switch option {
            case .pfx(let password):
                let pfxURL = outputURL.appending(name, extension: "pfx")

                try generatePFXCertificate(
                    pfxURL,
                    privateKey: privateKey,
                    certificate: certificate,
                    password: password
                )

                personalFileExchangeURL = pfxURL

            case .der:
                let derURL = outputURL.appending(name, extension: "cer")

                try generateDERCertificate(
                    derURL,
                    certificate: certificate
                )

                certificateDEREncodedURL = derURL
            }
        }

        return .init(
            certificateURL: certificate,
            privateKeyURL: privateKey,
            personalFileExchangeURL: personalFileExchangeURL,
            certificateDEREncodedURL: certificateDEREncodedURL
        )
    }
}

extension OpenSSL {

    func generatePrivateKey(_ url: URL) throws {
        try Process.zsh(
            """
            openssl genrsa \
                -out \(url.normalizePath)
            """
        ).waitUntilExit()
    }

    func generateSelfSignedCertificateRequest(_ url: URL, privateKey: URL) throws {
        try Process.zsh(
            """
            openssl req -new -sha256 \
                -key \(privateKey.normalizePath) \
                -out \(url.normalizePath) \
                -subj "/CN=localhost"
            """
        ).waitUntilExit()
    }

    func generateCertificate(
        _ url: URL,
        request: URL,
        privateKey: URL
    ) throws {
        try Process.zsh(
            """
            openssl req -x509 -sha256 -days 365 \
                -key \(privateKey.normalizePath) \
                -in \(request.normalizePath) \
                -out \(url.normalizePath)
            """
        ).waitUntilExit()
    }

    func generatePFXCertificate(
        _ url: URL,
        privateKey: URL,
        certificate: URL,
        password: String
    ) throws {
        try Process.zsh(
            """
            openssl pkcs12 -export \
                -inkey \(privateKey.normalizePath) \
                -in \(certificate.normalizePath) \
                -out \(url.normalizePath) \
                -passout pass:\(password)
            """
        ).waitUntilExit()
    }

    func generateDERCertificate(
        _ url: URL,
        certificate: URL
    ) throws {
        try Process.zsh(
            """
            openssl x509 -inform PEM -outform DER \
                -in \(certificate.normalizePath) \
                -out \(url.normalizePath)
            """
        ).waitUntilExit()

        try Process.zsh(
            """
            openssl x509 -noout -fingerprint -sha1 -inform dec \
                -in \(url.normalizePath)
            """
        ).waitUntilExit()
    }
}
#endif
