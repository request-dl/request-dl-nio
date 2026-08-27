# Downloading in the background

Schedule a download that keeps running even if your app is suspended or terminated, using `URLSession`'s background transfer support.

## Overview

``DownloadTask`` waits for a response and hands it back in the same call. ``BackgroundDownloadTask`` can't work that way: the whole point of a background transfer is that it can outlive the process that started it, possibly finishing in a completely different launch of your app. ``BackgroundDownloadTask/result()`` only confirms the download was scheduled — it returns as soon as that happens, not when the file is actually there.

```swift
try await BackgroundDownloadTask(
    id: "episode-42",
    destination: episodesDirectory.appendingPathComponent("episode-42.mp3")
) {
    BaseURL("api.example.com")
    Path("episodes/42/audio")
}
.result()
```

`id` is yours to choose — it's how you tell this download apart from every other one in ``BackgroundDownloads/Event``, described below. `destination` is where the file ends up; anything already there is overwritten once the download finishes.

## Observing progress and completion

Because the call site that scheduled a download might not exist anymore by the time it finishes, there's no per-call completion handler or `async` sequence to await. Instead, register one handler for every background download in the app:

```swift
BackgroundDownloads.onEvent = { event in
    switch event {
    case .progress(let id, _, let bytesWritten, let totalBytesExpected):
        print("\(id): \(bytesWritten)/\(totalBytesExpected)")
    case .completed(let id, let destination):
        print("\(id) finished at \(destination)")
    case .failed(let id, _, let error):
        print("\(id) failed: \(error)")
    }
}
```

Set this once, as early as possible — ideally before your app finishes launching, and unconditionally on every launch, including one the system triggered only to deliver background events, where there's no user-visible UI yet for those events to update.

> Note: ``BackgroundDownloads`` is deliberately not part of ``BackgroundDownloadTask`` itself. A generic type's static members are per-specialization in Swift, and every `BackgroundDownloadTask<Content>` call site has its own concrete `Content` — a handler stored there would only ever see downloads created with that exact `Content` type.

## Reconnecting after a relaunch

For the system to be able to reconnect a background session to a suspended or relaunched app, forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` from your `UIApplicationDelegate`:

```swift
func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
) {
    BackgroundDownloads.handleEvents(
        forBackgroundURLSession: identifier,
        completionHandler: completionHandler
    )
}
```

This is required, not optional — without it, a download that finishes while your app is suspended or not running has no way to reconnect and report back through ``BackgroundDownloads/onEvent``.

## Cancelling a download

```swift
let wasRunning = await BackgroundDownloads.cancel(id: "episode-42")
```

There's no separate "cancelled" case in ``BackgroundDownloads/Event`` — a cancelled download is reported through ``BackgroundDownloads/onEvent`` as an ordinary `.failed` event, with `NSURLErrorCancelled` as its underlying error, the same way any other failure is. ``BackgroundDownloads/cancel(id:)`` returns `false` when there's nothing to cancel — the download already finished, failed, or never existed under that `id`.

## What's not supported yet

- **``SecureConnection``.** A request configured with one throws ``BackgroundDownloadUnsupportedConfigurationError`` before it's ever scheduled. A background download's delegate can be asked to answer a TLS challenge long after the process that built the original request is gone, with no `Property` tree left to rebuild a client identity or custom trust roots from — that gap isn't closed yet, so it's rejected up front rather than left to fail unpredictably after a relaunch.
- **Modifiers and interceptors.** ``BackgroundDownloadTask`` does not conform to ``RequestTask`` — its result doesn't arrive in-process the way every modifier/interceptor assumes.

## Topics

### Scheduling a download

- ``BackgroundDownloadTask``

### Observing and managing downloads

- ``BackgroundDownloads``
- ``BackgroundDownloads/Event``

### Errors

- ``BackgroundDownloadUnsupportedConfigurationError``
