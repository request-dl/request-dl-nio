/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct CertificatePropertyKey: EnvironmentKey {
    static var defaultValue: CertificateProperty = .additionalTrust
}

extension EnvironmentValues {

    var certificateProperty: CertificateProperty {
        get { self[CertificatePropertyKey.self] }
        set { self[CertificatePropertyKey.self] = newValue }
    }
}
