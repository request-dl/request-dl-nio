/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct CertificatePropertyKey: RequestEnvironmentKey {
    static var defaultValue: CertificateProperty? { nil }
}

extension RequestEnvironmentValues {

    var certificateProperty: CertificateProperty? {
        get { self[CertificatePropertyKey.self] }
        set { self[CertificatePropertyKey.self] = newValue }
    }
}
