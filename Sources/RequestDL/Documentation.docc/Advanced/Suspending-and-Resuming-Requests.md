# Suspending and resuming requests

Pause a transfer that is in progress and continue it later, and let a download carry on after its connection drops.

## Overview

Two independent features cover the two ways a transfer can stop:

- ``RequestController`` pauses and resumes a request on purpose, while its connection stays open.
- ``RequestTask/resumingDownloads(_:)`` reconnects a download whose connection was lost, and continues it from where it stopped.

Neither changes a request that doesn't ask for it. Both work with ``DataTask``, ``DownloadTask`` and ``UploadTask`` (reconnection applies to downloads only), on every executor.

### Suspending and resuming with a controller

Create a ``RequestController`` and attach it to a task with ``RequestTask/controller(_:)``. Call ``RequestController/suspend()`` and ``RequestController/resume()`` from anywhere, on any thread:

```swift
let controller = RequestController()

let task = DownloadTask {
    BaseURL("example.com")
    Path("/video.mp4")
}
.controller(controller)

// Later:
controller.suspend()
controller.resume()
```

Both calls are synchronous, never throw, and are safe to repeat. They do nothing to a request that has already finished.

A controller is a shared switch, not a handle on one request:

- It can be attached to any number of tasks, and ``RequestController/suspend()`` pauses all of them. Attach the same controller to every task of a ``GroupTask`` to pause the whole group.
- A task may have several controllers.
- Its state is sticky. A request that starts while the controller is suspended starts suspended, so there is no gap between creating a task and pausing it. ``RequestController/isSuspended`` tells you the current state.
- It works anywhere in a task chain, before or after `.decode`, `.map` and the other modifiers.

Cancelling is unchanged: cancel the `Task` that runs the request. That also ends a suspension, so a suspended request never needs to be resumed just to be cancelled.

#### What a suspension does

A suspension stops the *network*, not the reader. Bytes that were already buffered ahead of the reader keep arriving, so progress can advance a little after ``RequestController/suspend()``:

| | Bytes that can still arrive |
| --- | --- |
| Downloads on the `.nio` executor | about half a MiB |
| Downloads on the `.urlSession` executor | a few MiB, because CFNetwork reads ahead |
| Uploads | about a MiB, held by the operating system's socket buffers |

The connection stays open while suspended, so it is exposed to any idle timeout along the way: the client's own, the server's, and any proxy or load balancer in between. A suspension that outlives the connection ends the request like any dropped connection does, promptly and never by hanging. On the `.urlSession` executor a suspended upload fails with `URLError.timedOut` once its idle timeout passes; keep pauses short, or use a longer timeout for requests you intend to pause.

> Note: A controller has no effect on ``BackgroundDownloadTask``, which the operating system runs.

### Continuing a download after a lost connection

A download that loses its connection midway fails, unless you opt in with ``RequestTask/resumingDownloads(_:)``:

```swift
try await DownloadTask {
    BaseURL("example.com")
    Path("/video.mp4")
}
.resumingDownloads(.enabled(maximumAttemptsWithoutProgress: 3, delay: 1))
.result()
```

When the connection drops, RequestDL sends a new request for the rest of the body, with an HTTP `Range` header, and splices it onto what you already received. Your code sees one uninterrupted body.

It only does so when that is safe. A download is resumed only if all of these hold, and otherwise it fails on a lost connection exactly as it does without the modifier:

- the request is a `GET` without a `Range` header of its own;
- the original response is a `200` without a content coding (`Content-Encoding`);
- the response carries a strong validator: a strong `ETag`, or, without any `ETag`, a strong `Last-Modified`.

The continuation asks with `If-Range`, so a resource that changed in the meantime is never spliced onto the bytes of its old version. If the server answers with anything other than exactly the rest of the same representation, for example because the resource changed or the server ignores `Range`, the download fails with an error and none of that response reaches you.

``DownloadResumptionPolicy`` controls the budget:

- `maximumAttemptsWithoutProgress` is how many reconnection attempts in a row may fail without a single new byte before the download fails for good. Any progress starts the count over, so a long download over a flaky network is not capped.
- `delay` is how many seconds to wait before each attempt.
- ``DownloadResumptionPolicy/disabled`` turns it off.

The modifier closest to the task wins, so `.resumingDownloads(.disabled)` placed after an inner `.resumingDownloads(.enabled())` does not undo it.

> Important: On the `.urlSession` executor, a chunked response that is cut exactly between two chunks, without its terminating chunk, is reported by the system as a successful, complete response. RequestDL can't tell it from a real one, so it can neither fail nor continue that download. The NIO executors detect it. When a truncated body would be a problem, use one of them, or verify the body yourself with a checksum or a length the server states separately.

A ``DataTask`` continues the same way, and needs nothing stored beyond what it already accumulates. Bodies too large for memory belong in a ``DownloadTask``.

### Continuing a download after the app was closed

A reconnection only helps while the request is still running. To continue a download in a new launch of the application, keep two things from the first one: the bytes you received, in a file of your own, and a ``DownloadResumptionPoint``, which is `Codable`.

```swift
// While downloading: keep what is needed to continue.
let result = try await DownloadTask {
    BaseURL("example.com")
    Path("/video.mp4")
}
.result()

// `nil` when this download can't be continued safely: nothing to keep, download it again later.
if let point = DownloadResumptionPoint(head: result.head, offset: 0) {
    try JSONEncoder().encode(point).write(to: pointURL)
}

// ... the application is closed, and later opened again ...

let saved = try JSONDecoder().decode(DownloadResumptionPoint.self, from: Data(contentsOf: pointURL))

let rest = try await DownloadTask {
    BaseURL("example.com")
    Path("/video.mp4")
}
.continuingDownload(from: saved.at(offset: bytesAlreadyOnDisk))
.result()
```

The library doesn't store a partial download: `offset` is the size of what you kept, which is also the one number that can't be wrong about how much was actually persisted. What you persist once is the point, which holds the validator of the resource; ``DownloadResumptionPoint/at(offset:)`` moves it to however many bytes are on disk when it is time to continue.

``DownloadResumptionPoint/init(head:offset:)`` returns `nil` when the download can't be continued safely, for the same reasons a reconnection wouldn't: the response has no strong validator, it carries a content coding, or it isn't a plain `200`. Check for `nil` and fall back to downloading again.

``RequestTask/continuingDownload(from:)`` asks the server for the rest, with `Range` and `If-Range`, and checks the answer before a single byte of it reaches you:

- The result is the *rest* of the resource: what comes after the offset. Its head is the `206` the server answered with.
- If the resource changed since the point was taken, the server sends it whole instead, and the task fails with a ``DownloadResumptionError``. Start the download again from the beginning.
- A point already at the end of the resource fails with ``DownloadResumptionError/Reason/alreadyComplete``, which isn't a failure: the file is complete. ``DownloadResumptionPoint/isComplete`` says so beforehand when the length is known.
- It always goes to the network, whatever the cache strategy: a cached copy of the whole resource isn't the rest of it.
- The request has to be a `GET` without a `Range` of its own, or it fails with ``DownloadResumptionError/Reason/requestNotResumable`` without being sent.

It works with ``DownloadTask`` and ``DataTask``, and combines with ``RequestTask/resumingDownloads(_:)``: if the connection is lost again, the download reconnects from everything received since the point.

> Note: A point is kept across launches, and across updates of your application, so its encoded format is versioned and stable. A point from a version this one doesn't know fails to decode instead of being misread.

> Note: For a transfer that has to keep going while the application isn't running, use ``BackgroundDownloadTask``, which the operating system runs.

### Using both together

The two combine. A controller that is suspended also holds back reconnection: a paused transfer never opens a new connection behind your back. If the pause outlives the connection, the download reconnects when you resume.

```swift
DownloadTask { ... }
    .resumingDownloads()
    .controller(controller)
```

To follow a request being suspended, resumed and reconnected as it happens, attach a ``RequestMonitor``: see <doc:Monitoring-requests>.

### Topics

- ``RequestController``
- ``RequestTask/controller(_:)``
- ``RequestTask/resumingDownloads(_:)``
- ``DownloadResumptionPolicy``
- ``RequestTask/continuingDownload(from:)``
- ``DownloadResumptionPoint``
- ``DownloadResumptionError``
