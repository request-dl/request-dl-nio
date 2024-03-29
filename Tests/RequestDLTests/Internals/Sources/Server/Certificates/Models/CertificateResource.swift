/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

struct CertificateResource: Hashable {

    let certificateURL: URL

    let privateKeyURL: URL
}

extension CertificateResource {

    init(
        _ path: String,
        in bundle: Bundle,
        format: Internals.Certificate.Format
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
    }
}
