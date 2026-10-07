# Suspending and resuming requests

Pause a transfer that is in progress and continue it later, and let a download or an upload carry on after its connection drops.

## Overview

Independent features cover the ways a transfer can stop:

- ``RequestController`` pauses and resumes a request on purpose, while its connection stays open.
- ``RequestTask/resumingDownloads(_:)`` reconnects a download whose connection was lost, and continues it from where it stopped.
- ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)`` does the same for an upload, by asking the server how much of it holds and sending the rest.

Neither changes a request that doesn't ask for it. All of them work on every executor.

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

``RequestTask/continuingDownload(from:whenChanged:)`` asks the server for the rest, with `Range` and `If-Range`, and checks the answer before a single byte of it reaches you:

- The result is the *rest* of the resource: what comes after the offset. Its head is the `206` the server answered with.
- If the resource changed since the point was taken (or the server doesn't support asking for a part), the server sends it whole instead, and by default the task fails with a ``DownloadResumptionError``: whatever you hold is yours to decide about, and nothing of the new resource reaches you. Start the download again from the beginning.
- Pass ``ChangedDownloadBehavior/restart`` as `whenChanged` to have the task ask again for the whole resource instead, which is what a browser does: `.continuingDownload(from: point, whenChanged: .restart)`. The result is then the whole new resource, and its head is a `200` where the rest is a `206`, which is how you tell them apart: on a `200`, discard what you held and write what comes from byte zero. A point that is already at the end, a request that can't be continued, and a server that refuses outright still fail, and so does a resource that changes later, while ``RequestTask/resumingDownloads(_:)`` reconnects, since by then bytes of the new one have already been handed on.
- A point already at the end of the resource fails with ``DownloadResumptionError/Reason/alreadyComplete``, which isn't a failure: the file is complete. ``DownloadResumptionPoint/isComplete`` says so beforehand when the length is known.
- It always goes to the network, whatever the cache strategy: a cached copy of the whole resource isn't the rest of it.
- The request has to be a `GET` without a `Range` of its own, or it fails with ``DownloadResumptionError/Reason/requestNotResumable`` without being sent.

It works with ``DownloadTask`` and ``DataTask``, and combines with ``RequestTask/resumingDownloads(_:)``: if the connection is lost again, the download reconnects from everything received since the point.

> Note: A point is kept across launches, and across updates of your application, so its encoded format is versioned and stable. A point from a version this one doesn't know fails to decode instead of being misread.

> Note: For a transfer that has to keep going while the application isn't running, use ``BackgroundDownloadTask``, which the operating system runs.

### Continuing an upload after a lost connection

An upload that loses its connection fails, and sending it again means sending all of it. A server that supports *resumable uploads* can say how much of the body it already has, and ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)`` uses that to send only the rest:

```swift
try await UploadTask {
    BaseURL("https://example.com")
    Path("/files/report.bin")
    RequestMethod(.put)
    Payload(url: reportURL)
}
.resumingUploads(.tus)
.collectData()
.result()
```

There are two protocols, and the server has to speak the one that is asked for: it is never negotiated, since an upload that was created for a protocol the server doesn't speak isn't one it can be asked about afterwards.

- ``IETFResumableUpload``, written `.ietf`, is the one of the IETF HTTP working group (`draft-ietf-httpbis-resumable-upload`, written against revision 12). It is what `.resumingUploads()` uses when no protocol is given. The request you wrote is the one that creates the upload, and the response to the request that completes it is the response to the request you wrote.
- ``TUSResumableUpload``, written `.tus`, is tus 1.0. The upload is created by a `POST` to the URL of the request you wrote, whatever its method, and the response is tus's: it has no body, and it isn't a response of your application.

> Important: The IETF draft is not an RFC and can still change, so ``IETFResumableUpload`` is experimental.

What happens:

1. The upload is created, which is one more request, and the server answers with where it is. If the server answers the request you wrote with something that isn't a success (a `401`, say), that is the response of the upload, as it would be without any of this. If it doesn't say where the upload is, the task fails with ``UploadResumptionError/Reason/notSupported``.
2. The body is sent to the upload.
3. When the connection is lost, or the server answers that it can't say where the upload stands right now (a `5xx`, `408`, `425` or `429`), the request waits while a ``RequestController`` it is attached to is suspended, waits `delay` seconds, asks the server how much it holds, and sends the rest. A server that disagrees about where to continue from is believed.

`maximumAttemptsWithoutProgress` is how many attempts after a loss may end without the server holding a single new byte before the upload fails for good, with the failure of the last one. Any progress starts the count over, so a long upload over a flaky network is not capped.

What to know:

- Only a request with a body is an upload. A request without one is sent as it is.
- A body that is compressed as it is sent (see ``Property/compression(_:onDuplicateHeader:shouldCompressBodyData:)``) is compressed first, once, so that the offset the server holds means the same bytes for every attempt, and so that its length is known when the upload is created (tus declares it). It is kept in memory up to 8 MiB and in a temporary file beyond that, which goes away with the request.
- Upload progress, in a ``RequestMonitor``, counts what crossed the network, so the bytes that had to be sent again count again, and `total` can pass `expected` after a retry. Clamp it if you divide one by the other. The monitor sees one request: it starts once, reports `reconnecting(attempt:)` for each retry, and ends once.
- When the server holds the whole body but the response to the request that completed it was lost, a tus upload ends normally (the answer about the offset says as much), and an IETF upload fails with ``UploadResumptionError/Reason/completedWithoutResponse``: the response was your application's, and nothing else the server says takes its place.
- Nothing is kept between launches of the application. An upload that is abandoned stays on the server until it expires, so the server has to expire them.

When the request is cancelled, the server is told the upload is abandoned (an HTTP `DELETE`, the IETF draft's cancellation and tus's termination extension), so that it can free what it holds. This is best effort and never in the way of the cancellation: it is sent in the background, only for an upload that was created and isn't complete, and a failure leaves the upload to expire. Pass ``UploadCancellation/keepOnServer`` as `onCancellation` to leave it there instead.

A failure that is about the upload itself is an ``UploadResumptionError``; a failure of the connection that ends the last attempt is thrown as it is.

### Using both together

The two combine. A controller that is suspended also holds back reconnection, for a download and for an upload: a paused transfer never opens a new connection behind your back. If the pause outlives the connection, the transfer reconnects when you resume.

```swift
DownloadTask { ... }
    .resumingDownloads()
    .controller(controller)
```

To follow a request being suspended, resumed and reconnected as it happens, attach a ``RequestMonitor``: see <doc:Monitoring-requests>.

## Topics

- ``RequestController``
- ``RequestTask/controller(_:)``
- ``RequestTask/resumingDownloads(_:)``
- ``DownloadResumptionPolicy``
- ``RequestTask/continuingDownload(from:whenChanged:)``
- ``DownloadResumptionPoint``
- ``ChangedDownloadBehavior``
- ``DownloadResumptionError``
- ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``
- ``RequestTask/resumingUploads(maximumAttemptsWithoutProgress:delay:onCancellation:)``
- ``ResumableUploadProtocol``
- ``IETFResumableUpload``
- ``TUSResumableUpload``
- ``UploadCancellation``
- ``UploadResumptionError``
