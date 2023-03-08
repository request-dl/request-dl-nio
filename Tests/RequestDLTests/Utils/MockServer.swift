//
//  File.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

struct MockServer {

    static func startWithCA(
        url: URL,
        server: String,
        client: String,
        password: String
    ) async throws -> Process {
        let clientCrt = url.appending(client, extension: "crt").normalizePath
        let clientKey = url.appending(client, extension: "key").normalizePath
        let clientPfx = url.appending(client, extension: "pfx").normalizePath

        let serverCrt = url.appending(server, extension: "crt").normalizePath
        let serverKey = url.appending(server, extension: "key").normalizePath

        let process = try Process.zsh(
            """
            openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout \(clientKey) -out \(clientCrt) \
            -subj "/C=US/ST=New York/L=Brooklyn/O=Local Host Company/CN=localhost"
            openssl pkcs12 -export -in \(clientCrt) -inkey \(clientKey) -out \(clientPfx) \
            -passout pass:\(password)
            openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout \(serverKey) -out \(serverCrt) \
            -subj "/C=US/ST=New York/L=Brooklyn/O=Local Host Company/CN=localhost"
            echo "Hello World!" > index.txt
            openssl s_server -accept 8080 -CAfile \(clientCrt) -cert \(serverCrt) -key \(serverKey) -Verify 2 -WWW
            """
        )

        do {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        } catch {
            process.interrupt()
            throw error
        }

        return process
    }

    static func writeCertificatesIntoBundle(
        url: URL,
        server: String,
        client: String
    ) async throws {
        let serverData = try await DownloadCertificate(from: "https://localhost:8080").download()

        let bundleURL = Bundle.module.normalizedResourceURL

        let clientData = try Data(contentsOf: url.appending(client, extension: "pfx"))

        try serverData.write(
            to: bundleURL.appending(server, extension: "crt"),
            options: [.atomic, .noFileProtection]
        )

        try clientData.write(
            to: bundleURL.appending(client, extension: "pfx"),
            options: [.atomic, .noFileProtection]
        )
    }
}

extension URL {

    var normalizePath: String {
        let rawPath = pathComponents
            .map { $0.trimmingCharacters(in: .init(charactersIn: "/")) }
            .joined(separator: "/")

        return rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath
    }

    func appending(_ path: String, extension: String? = nil) -> URL {
        var url = appendingPathComponent(path)

        if let `extension` {
            url.appendPathExtension(`extension`)
        }

        return url
    }
}
