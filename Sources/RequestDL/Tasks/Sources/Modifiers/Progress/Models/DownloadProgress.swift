/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The same applies to `DownloadProgress`, but in this case, the method will be called when a certain number of bytes have been received.

 During the download process, there is an exact value available from SwiftNIO and AsyncHTTPClient. However, to ensure higher quality control over the application's state, the ``RequestDL/ReadingMode`` object is defined, which allows formatting the received data in fixed-size chunks or specific byte sequences.

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

 - Note: You can use `UploadTask` with `progress(download:)` as long as you add the ``RequestDL/RequestTask/collectBytes()`` method.
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
