/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct CertificatePropertyKey: PropertyEnvironmentKey {
    static var defaultValue: CertificateProperty?
}

extension PropertyEnvironmentValues {

    var certificateProperty: CertificateProperty? {
        get { self[CertificatePropertyKey.self] }
        set { self[CertificatePropertyKey.self] = newValue }
    }
}
