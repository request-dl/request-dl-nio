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

    private static func `extension`(for format: CertificateFormat) -> String {
        switch format {
        case .der:
            return "cer"
        case .pem:
            return "pem"
        }
    }

    init(
        _ path: String,
        in bundle: Bundle,
        format: CertificateFormat
    ) {
        let path = path.replacingOccurrences(of: "_", with: ".")

        self.certificateURL = bundle.url(
            forResource: "\(path).public",
            withExtension: Self.extension(for: format)
        ).unsafelyUnwrapped

        self.privateKeyURL = bundle.url(
            forResource: "\(path).private",
            withExtension: Self.extension(for: format)
        ).unsafelyUnwrapped

        self.pskURL = bundle.url(
            forResource: "\(path).psk",
            withExtension: "pem"
        ).unsafelyUnwrapped
    }
}
