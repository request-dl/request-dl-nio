/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum CertificateProperty: Sendable, Hashable {
    #if !canImport(Network)
    case chain
    #endif
    case trust
    case additionalTrust
}
