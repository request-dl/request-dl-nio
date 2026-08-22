# Using progress for upload and download requests

Explore how to monitor your requests and track the progress of each operation precisely.

## Overview

The way SwiftNIO and AsyncHTTPClient send and receive data from the server allows for implementing a range of interesting features to handle the raw bytes involved in the operation.

Whether sending a ``RequestDL/Payload`` or a ``RequestDL/Form``, it is possible to serialize the transmission into parts and monitor the upload progress. The same applies to download, as the same process happens internally.

### Monitors

Exploring this feature in RequestDL involves separating the concepts of upload and download, which are represented through the ``RequestDL/AsyncResponse`` object. The foundation of RequestDL is asynchronous and is fully supported by the principles discussed here.

By using the ``RequestDL/Modifiers/Progress`` modifier, we process the sent and received bytes and notify the respective monitor at each stage. For this purpose, the ``RequestDL/UploadProgress`` and ``RequestDL/DownloadProgress`` have been implemented.

Implement ``RequestDL/UploadProgress`` and ``RequestDL/DownloadProgress`` with your own monitor objects, then attach them with ``RequestDL/RequestTask/progress(upload:)``, ``RequestDL/RequestTask/progress(download:)-20p6u``, or the combined ``RequestDL/RequestTask/progress(upload:download:)``:

```swift
struct PrintUploadProgress: UploadProgress {
    func upload(_ chunkSize: Int, totalSize: Int) {
        print("Uploaded \(chunkSize) of \(totalSize) bytes")
    }
}

struct PrintDownloadProgress: DownloadProgress {
    func download(_ slice: Data, totalSize: Int) {
        print("Downloaded \(slice.count) of \(totalSize) bytes")
    }
}

let result = try await UploadTask {
    BaseURL("apple.com")
    Payload(url: video, contentType: .mp4)
        .payloadChunkSize(8_192)
}
.progress(upload: PrintUploadProgress(), download: PrintDownloadProgress())
.result()

print(result.payload)
```

> Tip: ``RequestDL/RequestTask/progress(upload:)`` is available on any task whose result is ``RequestDL/AsyncResponse`` (such as ``RequestDL/UploadTask``), while ``RequestDL/RequestTask/progress(download:)-20p6u`` is available once the task result has already been narrowed to bytes (such as ``RequestDL/DownloadTask``). The combined `progress(upload:download:)` used above chains both in a single call.

## Topics

### Related Documentation

- <doc:Exploring-payload>

### The essentials tasks

- ``RequestDL/UploadTask``
- ``RequestDL/DownloadTask``

### Meet the progress

- ``RequestDL/UploadProgress``
- ``RequestDL/DownloadProgress``
- ``RequestDL/Progress``

### Discover the modifiers

- ``RequestDL/Modifiers/Progress``
- ``RequestDL/Modifiers/CollectBytes``
- ``RequestDL/Modifiers/CollectData``
