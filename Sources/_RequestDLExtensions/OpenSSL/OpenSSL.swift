/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
public struct OpenSSL {

    private let name: String
    private let format: OpenSSLFormat

    private let privateKeyPassword: String?
    private let pksPassword: String?

    public init(
        _ name: String = #file,
        format: OpenSSLFormat = .pem,
        with options: [OpenSSLOption] = []
    ) {
        self.format = format
        
        self.name = URL(fileURLWithPath: name)
            .deletingPathExtension()
            .lastPathComponent

        var privateKeyPassword: String?
        var pksPassword: String?

        for option in options {
            switch option {
            case .pks(let password):
                pksPassword = password
            case .privateKey(let password):
                privateKeyPassword = password
            }
        }

        self.privateKeyPassword = privateKeyPassword
        self.pksPassword = pksPassword
    }
}

extension OpenSSL {

    public func certificate() throws -> OpenSSLCertificate {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL_OpenSSL.\(UUID())")

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var privateKey = outputURL.appending(name, extension: "private.pem")
        try generatePrivateKey(privateKey)

        let selfSignedCertificateRequest = outputURL.appending(name, extension: "crs")
        try generateSelfSignedCertificateRequest(selfSignedCertificateRequest, privateKey: privateKey)

        var certificate = outputURL.appending(name, extension: "pem")

        try generateCertificate(certificate, request: selfSignedCertificateRequest, privateKey: privateKey)

        var pksURL: URL?

        if let pksPassword {
            let url = outputURL.appending(name, extension: "pks.pem")

            try generatePKCS12Certificate(
                url,
                privateKey: privateKey,
                certificate: certificate,
                password: pksPassword
            )

            pksURL = url
        }

        if format == .der {
            try generateDERCertificate(&certificate)
            try generateDERPrivateKey(&privateKey)
        }

        return .init(
            certificateURL: certificate,
            privateKeyURL: privateKey,
            pksURL: pksURL,
            pksPassword: pksPassword
        )
    }
}

extension OpenSSL {

    func generatePrivateKey(_ url: URL) throws {
        let password = privateKeyPassword.map { "-passout pass:\($0) " } ?? ""

        try Process.zsh(
            """
            openssl genrsa \
                -out \(url.normalizePath) \
                \(password)\
                2048
            """
        ).waitUntilExit()
    }

    func generateSelfSignedCertificateRequest(_ url: URL, privateKey: URL) throws {
        let password = privateKeyPassword.map { "-passin pass:\($0) " } ?? ""

        try Process.zsh(
            """
            openssl req -new -sha256 \
                -key \(privateKey.normalizePath) \
                -out \(url.normalizePath) \
                \(password)\
                -subj "/CN=localhost"
            """
        ).waitUntilExit()
    }

    func generateCertificate(
        _ url: URL,
        request: URL,
        privateKey: URL
    ) throws {
        let password = privateKeyPassword.map { "-passin pass:\($0) " } ?? ""

        try Process.zsh(
            """
            openssl req -x509 -sha256 -days 365 \
                -key \(privateKey.normalizePath) \
                \(password)\
                -in \(request.normalizePath) \
                -out \(url.normalizePath)
            """
        ).waitUntilExit()
    }

    func generatePKCS12Certificate(
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

    func generateDERCertificate(_ certificateURL: inout URL) throws {
        let outputURL = certificateURL
            .deletingPathExtension()
            .appendingPathExtension("cer")

        try Process.zsh(
            """
            openssl x509 -inform PEM -outform DER \
                -in \(certificateURL.normalizePath) \
                -out \(outputURL.normalizePath)
            """
        ).waitUntilExit()

        try Process.zsh(
            """
            openssl x509 -noout -fingerprint -sha1 -inform dec \
                -in \(outputURL.normalizePath)
            """
        ).waitUntilExit()

        certificateURL = outputURL
    }

    func generateDERPrivateKey(_ privateKeyURL: inout URL) throws {
        let password = privateKeyPassword.map { "-passin pass:\($0) " } ?? ""

        let outputURL = privateKeyURL
            .deletingPathExtension()
            .appendingPathExtension("cer")

        try Process.zsh(
            """
            openssl rsa -inform PEM -outform DER \
                -in \(privateKeyURL.normalizePath) \
                \(password)\
                -out \(outputURL.normalizePath)
            """
        ).waitUntilExit()

        privateKeyURL = outputURL
    }
}
#endif
