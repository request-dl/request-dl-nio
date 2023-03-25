/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
public enum OpenSSLOption {

    /// String password
    case pks(String)

    /// String password
    case privateKey(String)
}
#endif
