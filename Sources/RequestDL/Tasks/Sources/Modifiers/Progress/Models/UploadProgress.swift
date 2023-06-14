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

    /**
     A method that is called each time a portion of the upload operation is completed.

     - Parameters:
       - bytesLength: The length of the bytes that were uploaded in this portion of the operation.
     */
    @available(*, deprecated, renamed: "upload(_:totalSize:)")
    func upload(_ bytesLength: Int)
}

extension UploadProgress {

    @available(*, deprecated)
    public func upload(_ chunkSize: Int, totalSize: Int) {
        upload(chunkSize)
    }

    @available(*, deprecated)
    func upload(_ bytesLength: Int) {}
}
