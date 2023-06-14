/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol used to define methods that represent the progress of a download operation.
 */
public protocol DownloadProgress {

    /**
     Notifies the progress of a download operation.

     - Parameters:
       - slice: The data slice downloaded in the current progress update.
       - totalSize: The total size of the download.
     */
    func download(_ slice: Data, totalSize: Int)

    /**
     A method that is called each time a part of the download operation is completed.

     - Parameters:
        - part: The data that was downloaded in this part of the operation.
        - length: The length of the data expected to be downloaded during the operation.
     */
    @available(*, deprecated, renamed: "download(_:totalSize:)")
    func download(_ part: Data, length: Int?)
}

extension DownloadProgress {

    @available(*, deprecated)
    func download(_ slice: Data, totalSize: Int) {
        download(slice, length: totalSize)
    }

    @available(*, deprecated)
    func download(_ part: Data, length: Int?) {}
}
