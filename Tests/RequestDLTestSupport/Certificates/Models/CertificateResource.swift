//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

struct CertificateResource: Hashable {

    let certificateURL: URL

    let privateKeyURL: URL

    let format: Internals.Certificate.Format
}

extension CertificateResource {

    /// - Parameter path: The fixture's subdirectory under `Resources`, e.g. `"client_password"`,
    /// which also names the file stem once its underscores are dotted:
    /// `client_password/client.password.public.pem`.
    init(
        _ path: String,
        format: Internals.Certificate.Format
    ) {
        self.format = format

        let dottedPath = path.replacingOccurrences(of: "_", with: ".")
        let directory = testResourcesDirectory.appendingPathComponent(path, isDirectory: true)

        self.certificateURL = directory.appendingPathComponent(
            "\(dottedPath).public.\(format.pathExtension)"
        )

        self.privateKeyURL = directory.appendingPathComponent(
            "\(dottedPath).private.\(format.pathExtension)"
        )
    }
}
