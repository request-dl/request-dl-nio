/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestDL/DownloadProgress/download(_:totalSize:)`` is called when a certain number of bytes have been received.

 During the download process, SwiftNIO and AsyncHTTPClient provide the precise values of available bytes for reading, even asynchronously.

 To maintain a high level of control over the application state, we can use the ``RequestDL/ReadingMode`` to receive data in a fixed size for reading or based on a specific byte sequence.

 Here's an example of the `GithubDownloadMonitor` definition:

 ```swift
 struct GithubDownloadMonitor: DownloadProgress {

     let closure: (Int, Int) -> Void

     func download(_ slice: Data, totalSize: Int) {
         closure(slice.count, totalSize)
     }
 }
 ```

 Then, we can use it as follows:

 ```swift
 DownloadTask {
     // Request specification
 }
 .progress(download: GithubDownloadMonitor(closure: closure))
 // Other methods
 ```

 > Note: You can use ``UploadTask`` with ``RequestTask/progress(download:)-20p6u`` as long as you add the ``RequestDL/RequestTask/collectBytes()`` method.
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
