//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if os(macOS)
struct OpenSSLCertificate {

    let certificateURL: URL

    let privateKeyURL: URL

    let pkcs12URL: URL?

    let pkcs12Password: String?

    let certificateDEREncodedURL: URL?
}

extension OpenSSLCertificate {

    func write(into bundle: Bundle) throws -> OpenSSLBundleReference {
        let prefixPath = "OpenSSL.\(UUID())/"

        let certificateResource = (
            path: prefixPath.appending(certificateURL.lastPathComponent),
            data: try Data(contentsOf: certificateURL)
        )

        let privateKeyResource = (
            path: prefixPath.appending(privateKeyURL.lastPathComponent),
            data: try Data(contentsOf: privateKeyURL)
        )

        let pkcs12Resource = try pkcs12URL.map {(
            path: prefixPath.appending($0.lastPathComponent),
            data: try Data(contentsOf: $0)
        )}

        let certificateDEREncodedResource = try certificateDEREncodedURL.map {(
            path: prefixPath.appending($0.lastPathComponent),
            data: try Data(contentsOf: $0)
        )}

        let resourceURL = bundle.normalizedResourceURL

        try FileManager.default.createDirectory(
            at: resourceURL.appendingPathComponent(prefixPath),
            withIntermediateDirectories: true
        )

        let resources = [
            certificateResource, privateKeyResource,
            pkcs12Resource, certificateDEREncodedResource
        ]

        for resource in resources {
            if let resource {
                let url = resourceURL.appendingPathComponent(resource.path)
                try resource.data.write(to: url, options: [.atomic, .noFileProtection])
            }
        }

        return .init(
            certificatePath: certificateResource.path,
            privateKeyPath: privateKeyResource.path,
            pkcs12Path: pkcs12Resource?.path,
            certificateDEREncodedPath: certificateDEREncodedResource?.path
        )
    }
}
#endif
