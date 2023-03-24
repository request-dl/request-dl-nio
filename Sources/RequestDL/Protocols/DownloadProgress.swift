/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol DownloadProgress {

    var contentLengthHeaderKey: String? { get }

    func download(_ part: Data, length: Int?)
}

extension DownloadProgress {

    public var contentLengthHeaderKey: String? {
        return nil
    }
}
