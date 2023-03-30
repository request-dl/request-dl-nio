/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct CertificateResource {

    public let certificateURL: URL

    public let privateKeyURL: URL

    public let pskURL: URL
}

extension CertificateResource {

    init(
        _ path: String,
        in bundle: Bundle,
        format: Certificate.Format
    ) {
        let path = path.replacingOccurrences(of: "_", with: ".")

        self.certificateURL = bundle.url(
            forResource: "\(path).public",
            withExtension: format.pathExtension
        ).unsafelyUnwrapped

        self.privateKeyURL = bundle.url(
            forResource: "\(path).private",
            withExtension: format.pathExtension
        ).unsafelyUnwrapped

        self.pskURL = bundle.url(
            forResource: "\(path).psk",
            withExtension: "pem"
        ).unsafelyUnwrapped
    }
}
