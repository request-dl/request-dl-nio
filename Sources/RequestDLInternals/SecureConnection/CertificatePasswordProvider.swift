/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol CertificatePasswordProvider {

    associatedtype Bytes: Collection where Bytes.Element == UInt8

    func callAsFunction() -> Bytes
}
