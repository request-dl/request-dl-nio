/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct CertificatePassword<Bytes: Collection>: CertificatePasswordProvider where Bytes.Element == UInt8 {

    let bytes: Bytes

    public init(_ bytes: Bytes) {
        self.bytes = bytes
    }

    public func callAsFunction() -> Bytes {
        bytes
    }
}
