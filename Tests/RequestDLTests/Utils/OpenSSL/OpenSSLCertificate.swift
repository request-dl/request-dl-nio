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

    let personalFileExchangeURL: URL?

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

        let personalFileExchangeResource = try personalFileExchangeURL.map {(
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
            personalFileExchangeResource, certificateDEREncodedResource
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
            personalFileExchangePath: personalFileExchangeResource?.path,
            certificateDEREncodedPath: certificateDEREncodedResource?.path
        )
    }
}
#endif
