/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `UploadProgress` protocol defines methods for tracking the progress of an upload operation.
 */
public protocol UploadProgress {

    /**
     Notifies the progress of an upload operation.

     - Parameters:
       - chunkSize: The size of each chunk during upload.
       - totalSize: The total size of the upload.
     */
    func upload(_ chunkSize: Int, totalSize: Int)
}
