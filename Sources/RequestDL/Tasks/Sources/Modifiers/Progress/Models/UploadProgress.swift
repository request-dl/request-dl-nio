/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol UploadProgress {

    func upload(_ bytesLength: Int)
}