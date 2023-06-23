/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestDL/UploadProgress/upload(_:totalSize:)`` is called when a certain number of
 bytes have been sent.

 If no value is specified for the payload chunk size, RequestDL automatically fragments the body in a 1:100 ratio,
 allowing for the implementation of a 100% progress bar with no additional code.

 Here's an example of the `GithubUploadMonitor`:

 ```swift
 struct GithubUploadMonitor: UploadProgress {

     let closure: (Int, Int) -> Void

     func upload(_ chunkSize: Int, totalSize: Int) {
         closure(chunkSize, totalSize)
     }
 }
 ```

 Then, we can use it as follows:

 ```swift
 UploadTask {
     // Request specification
 }
 .progress(upload: GithubUploadMonitor(closure: closure))
 // Other methods
 ```

 > Note: It's important to remember that you can manage how your data is sent using
 ``RequestDL/Property/payloadChunkSize(_:)``.
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
