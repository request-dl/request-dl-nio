/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS) || os(Linux)
public enum OpenSSLFormat {

    case der
    case pem
}
#endif
