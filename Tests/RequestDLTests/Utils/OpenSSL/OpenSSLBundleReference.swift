/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
struct OpenSSLBundleReference {

    let certificatePath: String

    let privateKeyPath: String

    let pkcs12Path: String?

    let certificateDEREncodedPath: String?
}
#endif
