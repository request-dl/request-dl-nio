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

> Tip: You can control how bytes are read by the client through ``RequestDL/ReadingMode``, which should be specified during request construction. This way, you can track the download progress using ``RequestDL/RequestTask/progress(download:)-20p6u``. To read the body by line or by separator instead, see <doc:Reading-lines>; the separator modes of ``RequestDL/ReadingMode`` are deprecated in its favor.

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

### Request metrics

A ``RequestDL/TaskResult`` carries what the request measured on the wire in ``RequestDL/TaskResult/metrics``: one ``RequestDL/RequestMetrics/Transaction`` for every exchange it went through, so a redirect that was followed shows up as one transaction per hop, in order.

```swift
let result = try await DataTask {
    // Property specifications
}
.result()

for transaction in result.metrics?.transactions ?? [] {
    print(transaction.url?.absoluteString ?? "-")

    if let connection = transaction.connection {
        print("reused:", connection.isReused)
        print("tls:", connection.secureConnection?.duration ?? 0)
    }
}
```

Both executors fill the same values, with a few phases only one of them can observe. Anything that was not reached, or that the executor cannot observe, is `nil` rather than zero:

- A reused connection did not go through ``RequestDL/RequestMetrics/Connection/domainLookup``, ``RequestDL/RequestMetrics/Connection/connect`` or ``RequestDL/RequestMetrics/Connection/secureConnection``, so those are `nil` for it.
- ``RequestDL/RequestMetrics/Connection/tlsCipherSuite`` is only known to `URLSession` and to AsyncHTTPClient over the Network framework.
- The header byte counts are `nil` for HTTP/2.
- ``RequestDL/RequestMetrics/Transaction/queued`` is only reported by AsyncHTTPClient.
- ``RequestDL/RequestMetrics/Transaction/error`` is the error of the exchange that failed. A request that fails as a whole throws and has no ``RequestDL/TaskResult``, so it is visible when a body fails after the response head, or when a download continued from a failed attempt.
- ``RequestDL/RequestMetrics/fetchInterval`` is `nil` while the last transaction has not finished or failed.
- ``RequestDL/TaskResult/metrics`` is `nil` only when there is nothing to measure, as with a ``RequestDL/MockedTask``. A response served from the cache is a transaction whose ``RequestDL/RequestMetrics/Transaction/source`` is `.cache`, with no connection.
- A cached response that was revalidated first has the conditional request in front of it, with the source `.revalidation`. It is a request you did not make, so filter by source when you add the transactions up. If the revalidation finds the cache stale, the transaction after it has the source `.network`.

> Note: With ``RequestDL/Session/Executor/nio``, the DNS lookup is only reported when the session opts in with ``RequestDL/Session/collectDNSMetrics(_:)``. Reporting it makes the client resolve host names with its own implementation instead of SwiftNIO's default one, which is why it is off by default.

Metrics are read when asked for. A ``RequestDL/DataTask`` has collected the whole body by the time its result exists, so they are complete. For ``RequestDL/DownloadTask``, the last transaction only ends once the body has been consumed, so read ``RequestDL/TaskResult/metrics`` after that.

### BackgroundDownloadTask

Every task above runs and reports back in the same process. ``RequestDL/BackgroundDownloadTask`` is different on purpose: it schedules a download that keeps running even if your app is suspended or terminated, using `URLSession`'s background transfer support, and does not conform to ``RequestDL/RequestTask``. See <doc:Downloading-in-the-Background> for how to schedule one and observe when it finishes.

## Topics

### The basics

- ``RequestDL/RequestTask``
- ``RequestDL/TaskResultPrimitive``
- ``RequestDL/TaskError``
- ``RequestDL/TaskResult``
- ``RequestDL/RequestMetrics``

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
