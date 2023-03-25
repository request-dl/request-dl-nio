/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
public struct OpenSSLBundleReference {

    public let certificatePath: String

    public let privateKeyPath: String

    public let pksPath: String?
}
#endif