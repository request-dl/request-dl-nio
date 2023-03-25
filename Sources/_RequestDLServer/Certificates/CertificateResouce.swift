/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct CertificateResouce {

    public let certificateURL: URL

    public let privateKeyURL: URL

    public let pskURL: URL
}

extension CertificateResouce {
    
    init(
        _ path: String,
        in bundle: Bundle,
        format: CertificateFormat
    ) {
        let path = path.replacingOccurrences(of: "_", with: ".")

        self.certificateURL = bundle.url(
            forResource: "\(path).public",
            withExtension: format.extension
        ).unsafelyUnwrapped

        self.privateKeyURL = bundle.url(
            forResource: "\(path).private",
            withExtension: format.extension
        ).unsafelyUnwrapped

        self.pskURL = bundle.url(
            forResource: "\(path).psk",
            withExtension: "pem"
        ).unsafelyUnwrapped
    }
}
