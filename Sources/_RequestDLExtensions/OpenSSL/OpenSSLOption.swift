/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS) || os(Linux)
public enum OpenSSLOption {

    /// String password
    case pks(String)

    /// String password
    case privateKey(String)
}
#endif
