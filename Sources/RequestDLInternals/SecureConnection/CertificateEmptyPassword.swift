/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct CertificateEmptyPassword: CertificatePasswordProvider {

    public typealias Bytes = [UInt8]

    public func callAsFunction() -> Bytes {
        []
    }
}
