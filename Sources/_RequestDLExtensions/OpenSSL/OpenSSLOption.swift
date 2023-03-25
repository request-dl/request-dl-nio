/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
public enum OpenSSLOption {

    /// String password
    case pkcs12(String)

    case der
}
#endif
