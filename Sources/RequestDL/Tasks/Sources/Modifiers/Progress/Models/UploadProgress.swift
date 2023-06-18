/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 During the definition of your request, you can include the upload monitor to receive notifications when a sequence of bytes is sent.

 - Note: It's important to remember that you can manage how your data is sent using ``RequestDL/Property/payloadChunkSize(_:)``.

 If no value is specified for the payload part length, RequestDL automatically fragments the parts in a 1:100 ratio, allowing for the implementation of a 100% progress bar.

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
