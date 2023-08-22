/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestDL/Progress`` protocol combines both ``RequestDL/UploadProgress`` and
 ``RequestDL/DownloadProgress``, allowing for the implementation of a single object.

 ```swift
 struct GithubMonitor: Progress {

     let uploadClosure: (Int, Int) -> Void
     let downloadClosure: (Int, Int) -> Void

     func upload(_ chunkSize: Int, totalSize: Int) {
         uploadClosure(chunkSize, totalSize)
     }

     func download(_ slice: Data, totalSize: Int) {
         downloadClosure(slice.count, totalSize)
     }
 }
 ```

 Then, we can use it as follows:

 ```swift
 UploadTask {
     // Request specification
 }
 .progress(GithubMonitor(
     uploadClosure: uploadClosure,
     downloadClosure: downloadClosure,
 ))
 // Other methods
 ```
 */
public typealias Progress = UploadProgress & DownloadProgress
