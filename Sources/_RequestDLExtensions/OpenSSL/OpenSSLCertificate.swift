/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
public struct OpenSSLCertificate {

    public let certificateURL: URL

    public let privateKeyURL: URL

    public let pksURL: URL?

    public let pksPassword: String?
}

extension OpenSSLCertificate {

    public func write(into bundle: Bundle) throws -> OpenSSLBundleReference {
        let prefixPath = "OpenSSL.\(UUID())/"

        let certificateResource = (
            path: prefixPath.appending(certificateURL.lastPathComponent),
            data: try Data(contentsOf: certificateURL)
        )

        let privateKeyResource = (
            path: prefixPath.appending(privateKeyURL.lastPathComponent),
            data: try Data(contentsOf: privateKeyURL)
        )

        let pksResource = try pksURL.map {(
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
            pksResource
        ]

        for resource in resources {
            if let resource {
                let url = resourceURL.appendingPathComponent(resource.path)
                try resource.data.write(to: url, options: [.atomic])
            }
        }

        return .init(
            certificatePath: certificateResource.path,
            privateKeyPath: privateKeyResource.path,
            pksPath: pksResource?.path
        )
    }
}
#endif
