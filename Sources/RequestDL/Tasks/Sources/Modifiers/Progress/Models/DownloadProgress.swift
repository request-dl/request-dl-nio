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
}
