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

> Warning: The element must conform to the `Hashable` protocol.

```swift
func makeMultipleRequest() async throws -> GroupResult<Int, TaskResult<Data>> {
    try await GroupTask([0, 1, 2, 3]) { page in
        DataTask {
            BaseURL("apple.com")
            Path("results")
            Query(name: "page", value: page)
        }
    }
    .result()
}

let results = try await makeMultipleRequest()

for (page, result) in results {
    switch result {
    case .success(let taskResult):
        print(page, taskResult.payload)
    case .failure(let error):
        print(page, error)
    }
}
```

### MockedTask

``RequestDL/MockedTask`` mirrors a resolved request back as its own response, without performing any real network call — useful for tests and previews where you want deterministic data and no dependency on a live server, or simply to inspect exactly what a request would look like.

You specify the response head — `version`, `status`, and `isKeepAlive` — along with a ``RequestDL/Property`` block describing the request, exactly as you would for a real one. Every header it would carry (including `Content-Type`/`Content-Length` from ``RequestDL/Payload``) is copied onto the response, and ``RequestDL/Payload``'s bytes become the response body.

```swift
let result = try await MockedTask(
    status: .init(code: 200, reason: "Ok")
) {
    Payload(
        verbatim: """
        {
            "id": 1,
            "name": "John Doe"
        }
        """,
        contentType: .json
    )
}
.collectData()
.result()

print(result.payload)
```

> Tip: ``RequestDL/MockedTask`` returns an ``RequestDL/AsyncResponse``, just like ``RequestDL/UploadTask``. Use ``RequestDL/RequestTask/collectData()-3viv5`` to collapse it into a ``RequestDL/TaskResult`` the same way ``RequestDL/DataTask`` does.

Use the `headers` parameter to overlay something that is not part of the request itself — it takes precedence over a mirrored header with the same name. Use `delay` to simulate network latency, and ``RequestDL/MockedTask/init(throwing:delay:)`` to simulate a transport-level failure instead of a response:

```swift
struct OfflineError: Error {}

let task = MockedTask(throwing: OfflineError(), delay: .seconds(1))
```

### BackgroundDownloadTask

Every task above runs and reports back in the same process. ``RequestDL/BackgroundDownloadTask`` is different on purpose: it schedules a download that keeps running even if your app is suspended or terminated, using `URLSession`'s background transfer support, and does not conform to ``RequestDL/RequestTask``. See <doc:Downloading-in-the-Background> for how to schedule one and observe when it finishes.

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

### Downloading in the background

- <doc:Downloading-in-the-Background>
