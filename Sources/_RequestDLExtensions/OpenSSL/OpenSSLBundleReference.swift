/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS) || os(Linux)
public struct OpenSSLBundleReference {

    public let certificatePath: String

    public let privateKeyPath: String

    public let pksPath: String?
}
#endif
