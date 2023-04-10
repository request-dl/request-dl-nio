/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol used to define methods and properties that represent the progress
 of a download operation.
 */
public protocol DownloadProgress {

    /// The header key that represents the total content length of the download operation.
    var contentLengthHeaderKey: String? { get }

    /**
     A method that is called each time a part of the download operation is completed.

     - Parameters:
        - part: The data that was downloaded in this part of the operation.
        - length: The length of the data expected to be downloaded during the operation.
     */
    func download(_ part: Data, length: Int?)
}

extension DownloadProgress {

    /**
     The default implementation of the contentLengthHeaderKey property, which returns
     the "Content-Length" header key.
     */
    public var contentLengthHeaderKey: String? {
        "Content-Length"
    }
}
