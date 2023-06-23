# Exploring the task diversity

Discover the available variations to execute a request according to the specific needs of each endpoint.

## Overview

The construction of requests in RequestDL was shaped according to Foundation concepts. Combining with the implementation of ``RequestDL/RequestTask`` and async/await, it was possible to provide ``RequestDL/UploadTask``, ``RequestDL/DownloadTask``, and ``RequestDL/DataTask``.

Each form of creating a request has a unique purpose, which is directly related to the result that these objects return.

### UploadTask

`UploadTask` was developed to allow the use of ``RequestDL/AsyncResponse`` and obtain information about each byte sent during the upload process. This is advantageous if you are considering implementing a progress bar that informs the user about the upload status.

> Tip: You have fine-grained control over the upload with ``RequestDL/Property/payloadChunkSize(_:)``. Just specify it during the request specification to get the upload process with ``RequestDL/RequestTask/progress(upload:)`` in the way you prefer.

Here's an example without abstracting the solution so you can learn the most basic way to use ``RequestDL/UploadTask``:

```swift
let response = try await UploadTask {
    BaseURL("apple.com")
    // Other specifications
    Payload(url: video, contentType: .mp4)
        .payloadChunkSize(8_192)
}
.result()

for try await step in response {
    switch step {
    case .upload(let step):
        print(step.chunkSize, step.totalSize)
    case .download(let step):
        // Handle download step
    }
}
```

Learn more about using [async/await](<doc:Swift-concurrency>) from the beginning.

Since every request always starts with the upload process, followed by the download, using ``RequestDL/UploadTask`` gives you access to all the stages of a request.

### DownloadTask

``RequestDL/DownloadTask`` results in ``RequestDL/ResponseHead`` and ``RequestDL/AsyncBytes``, disregarding the upload information. Through these objects, it is already possible to obtain all the data of the request, whether it was successful or not, and also monitor the byte transmission to the server, thanks to `async/await`.

> Tip: You can control how bytes are read by the client through ``RequestDL/ReadingMode``, which should be specified during request construction. This way, you can track the download progress using ``RequestDL/RequestTask/progress(download:)-20p6u``.

Here's an example without available abstractions to explore the usage of ``RequestDL/DownloadTask``:

```swift
let downloadStep = try await DownloadTask {
    BaseURL("apple.com")
    // Other specifications
    Payload(url: video, contentType: .mp4)
        .payloadChunkSize(8_192)
}
.result()

let asyncBytes = downloadStep.bytes

for try await bytes in asyncBytes {
    print(bytes.count, asyncBytes.totalSize)
}
```

When using ``RequestDL/DownloadTask``, you need to implement a way to handle and combine the received bytes to obtain the complete `Data`.

### DataTask

``RequestDL/DataTask`` is the default way to make requests in RequestDL. The result is a ``RequestDL/TaskResult`` encapsulating the `Data`. If the endpoint you are consuming doesn't have any rules for uploading or downloading information, you can use it as the recommended option.

Here's the standard usage:

```swift
let result = try await DataTask {
    // Property specifications
}
.result()

print(result.payload)
```

> Tip: Explore the use of [modifiers and interceptors](<doc:Modifiers-and-Interceptors>) to enhance your requests.

### GroupTask

``RequestDL/GroupTask`` is useful for grouping multiple simultaneous calls into a single one. To use it, you need to have a sequence that will be converted into a ``RequestDL/RequestTask``.

Then, for each item in the sequence, you will have access to its individual result through ``RequestDL/GroupTask/result()``, which is a dictionary where the keys are identified by the sequence element.

- Warning: The element must conform to the `Hashable` protocol.

## Topics

### The basics

- ``RequestDL/RequestTask``
- ``RequestDL/TaskResultPrimitive``
- ``RequestDL/TaskError``
- ``RequestDL/TaskResult``

### Meet the tasks

- ``RequestDL/UploadTask``
- ``RequestDL/DownloadTask``
- ``RequestDL/DataTask``
- ``RequestDL/RequestFailureError``

### Performing multiple tasks

- ``RequestDL/GroupTask``
- ``RequestDL/GroupResult``

### Discovering the response

- ``RequestDL/ResponseHead``
- ``RequestDL/ResponseHead/Status-swift.struct``
- ``RequestDL/ResponseHead/Version-swift.struct``
- ``RequestDL/StatusCode``
- ``RequestDL/StatusCodeSet``

### Receiving the headers

- ``RequestDL/HTTPHeaders``

### Modifying and intercepting the responses 

- <doc:Modifiers-and-Interceptors>

### Monitoring the progress

- <doc:Upload-and-download-progress>

### Testing and debugging

- ``RequestDL/MockedTask``
