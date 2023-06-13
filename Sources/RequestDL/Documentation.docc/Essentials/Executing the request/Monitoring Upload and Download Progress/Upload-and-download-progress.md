# Using progress for upload and download requests

Explore how to monitor your requests and track the progress of each operation precisely.

## Overview

The way SwiftNIO and AsyncHTTPClient send and receive data from the server allows for implementing a range of interesting features to handle the raw bytes involved in the operation.

Whether sending a ``RequestDL/Payload`` or a ``RequestDL/Form``, it is possible to serialize the transmission into parts and monitor the upload progress. The same applies to download, as the same process happens internally.

## Monitors

Exploring this feature in RequestDL involves separating the concepts of upload and download, which are represented through the ``RequestDL/AsyncResponse`` object. The foundation of RequestDL is asynchronous and is fully supported by the principles discussed here.

By using the ``RequestDL/Modifiers/Progress`` modifier, we process the sent and received bytes and notify the respective monitor at each stage. For this purpose, the ``RequestDL/UploadProgress`` and ``RequestDL/DownloadProgress`` have been implemented.

### UploadProgress

During the definition of your request, you can include the upload monitor to receive notifications when a sequence of bytes is sent.

- Note: It's important to remember that you can manage how your data is sent using ``RequestDL/Property/payloadPartLength(_:)``.

If no value is specified for the payload part length, RequestDL automatically fragments the parts in a 1:100 ratio, allowing for the implementation of a 100% progress bar.

Here's an example of the `GithubUploadMonitor`:

```swift
struct GithubUploadMonitor: UploadProgress {

    let closure: (Int) -> Void

    func upload(_ bytesLength: Int) {
        closure(bytesLength)
    }
}
```

Then, we can use it as follows:

```swift
UploadTask {
    // Request specification
}
.uploadProgress(GithubUploadMonitor(closure: closure))
// Other methods
```

### DownloadProgress

The same applies to `DownloadProgress`, but in this case, the method will be called when a certain number of bytes have been received.

During the download process, there is an exact value available from SwiftNIO and AsyncHTTPClient. However, to ensure higher quality control over the application's state, the ``RequestDL/ReadingMode`` object is defined, which allows formatting the received data in fixed-size chunks or specific byte sequences.

Here's an example of the `GithubDownloadMonitor` definition:

```swift
struct GithubDownloadMonitor: DownloadProgress {

    let closure: (Int, Int?) -> Void

    func download(_ part: Data, length: Int?) {
        closure(part.count, length)
    }
}
```

Then, we can use it as follows:

```swift
DownloadTask {
    // Request specification
}
.downloadProgress(GithubDownloadMonitor(closure: closure))
// Other methods
```

- Note: You can use `UploadTask` with `downloadProgress(_:)` as long as you add the ``RequestDL/RequestTask/ignoresUploadProgress()`` method.

### Progress

The ``RequestDL/Progress`` protocol combines both `UploadProgress` and `DownloadProgress`, allowing for the implementation of a single object.

```swift
struct GithubMonitor: Progress {

    let uploadClosure: (Int) -> Void
    let downloadClosure: (Int, Int?) -> Void

    func upload(_ bytesLength: Int) {
        uploadClosure(bytesLength)
    }

    func download(_ part: Data, length: Int?) {
        downloadClosure(part.count, length)
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
