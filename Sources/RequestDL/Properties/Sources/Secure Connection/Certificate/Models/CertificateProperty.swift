/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum CertificateProperty: Sendable, Hashable {
    case chain
    case trust
    case additionalTrust
}
