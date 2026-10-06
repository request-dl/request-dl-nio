# Monitoring requests

Follow how much of a request and its response has crossed the network, and what state each request is in, for any task.

## Overview

A ``RequestMonitor`` is told about a request as it runs. Attach one to any task with ``RequestTask/monitor(_:)``:

```swift
struct DownloadMonitor: RequestMonitor {
    func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {
        if let expected {
            print("\(total * 100 / expected)%")
        }
    }

    func request(_ execution: RequestExecution, didChange state: RequestState) {
        print(state)
    }
}

let data = try await DataTask {
    BaseURL("example.com")
    Path("/video.mp4")
}
.monitor(DownloadMonitor())
.extractPayload()
.result()
```

Every method has an empty default implementation, so a monitor only implements what it needs. It works with ``DataTask``, ``DownloadTask``, ``UploadTask`` and ``GroupTask``, anywhere in a task chain, and a task may have several monitors.

### Progress

``RequestMonitor/request(_:didUpload:total:of:)`` reports the request body going out, and ``RequestMonitor/request(_:didDownload:total:of:)`` the response body coming in. Each call says how many bytes were added since the previous one (`bytes`), how many there are in all (`total`), and what the total is expected to reach (`expected`) when that is known:

- for an upload, the size of the request body (for one made resumable with ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``, the size of what is sent, which for a compressed body is its compressed size);
- for a download, the response's `Content-Length`. It is `nil` for a chunked response, and for one with a content coding, because the transport may already have decoded the bytes being counted.

Bytes are counted where they cross the network, not where your code reads them. For that reason `total` is never limited to `expected`: when a resumable upload has to send part of the body again after a loss, those bytes count again, and `total` can pass `expected`. A download's progress keeps advancing while you aren't reading its body, up to what the transport buffers ahead of you, and it stops when the transfer does, for instance while suspended by a ``RequestController``.

### State

``RequestMonitor/request(_:didChange:)`` reports each ``RequestState`` an execution goes through. It always begins with ``RequestState/started``. It may pass through ``RequestState/suspended``, ``RequestState/resumed`` and ``RequestState/reconnecting(attempt:)``, when a controller, ``RequestTask/resumingDownloads(_:)`` or ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)`` are in use. It always ends with exactly one of ``RequestState/finished`` or ``RequestState/failed(_:)``, after which nothing more is reported for that execution. Cancelling a request ends it as failed.

A response served from the cache finishes right after it starts, having moved nothing on the network.

### Metrics

``RequestMonitor/request(_:didCollect:)`` reports each ``RequestMetrics/Transaction`` of an execution: one exchange on the wire, with the phases it went through and the connection it ran on. A request that follows a redirect or continues a download reports one for every exchange. A response served from the cache is one with `.cache` as its ``RequestMetrics/Transaction/source``, and the conditional request that asked whether the cache still held is one with `.revalidation`, reported ahead of whatever followed it.

It is independent of how the request ends. A request that fails as a whole throws, so there is no ``TaskResult`` to read ``TaskResult/metrics`` from, but a monitor still hears about the transactions it went through:

```swift
struct MetricsMonitor: RequestMonitor {
    func request(_ execution: RequestExecution, didCollect transaction: RequestMetrics.Transaction) {
        print(execution.url, transaction.connection?.isReused ?? false, transaction.responseStart != nil)
    }
}
```

When it arrives depends on the executor. AsyncHTTPClient reports a transaction before the execution ends. `URLSession` reports it once its task is done, which can be after the final ``RequestState``, and it only reports an error for the task as a whole, so ``RequestMetrics/Transaction/error`` can be missing from a transaction even when the execution failed. The ``RequestState/failed(_:)`` state carries the error.

### Telling requests apart

Every call includes a ``RequestExecution``, which identifies the run it is about (`id`, `url`, `method`). When one monitor is attached to a ``GroupTask``, that is how you know which of its requests an event belongs to. Two runs of the same request, such as the attempts of a `.retry`, are two executions.

### A monitor that takes its time

Events reach a monitor in order, one at a time, on a task of their own, so a slow monitor never slows the transfer down. It doesn't make progress pile up either: byte counts that arrive while a previous call is still running are merged into the next one, whose `bytes` is their sum and whose `total` is the latest. State changes are never merged or skipped.

### Migrating from `progress`

``RequestTask/progress(upload:download:)`` and its variants are deprecated in favour of monitors. They keep working, but two things differ:

- `progress(...)` reports as your code consumes the response, and only exists for tasks whose result is a stream. A monitor reports as the bytes cross the network, and works with every task, `DataTask` included.
- `progress(...)` also collects the response body into `Data`. A monitor only observes. To get the same result, follow `monitor(_:)` with `collectData()`:

```swift
// Before
DownloadTask { ... }
    .progress(download: MyDownloadProgress())

// After
DownloadTask { ... }
    .monitor(MyMonitor())
    .collectData()
```

### Topics

- ``RequestMonitor``
- ``RequestExecution``
- ``RequestState``
- ``RequestTask/monitor(_:)``
