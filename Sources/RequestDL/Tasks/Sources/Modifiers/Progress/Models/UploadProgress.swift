/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol used to define methods and properties that represent the progress of an upload operation.
 */
public protocol UploadProgress {

    /**
     A method that is called each time a portion of the upload operation is completed.

     - Parameters:
       - bytesLength: The length of the bytes that were uploaded in this portion of the operation.
     */
    func upload(_ bytesLength: Int)
}
