/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum Response {
    case upload(Int)
    case download(ResponseHead, AsyncBytes)
}
