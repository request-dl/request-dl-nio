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

To also get what it takes to carry on later, see <doc:Downloading-in-the-Background#Continuing-a-download-that-stopped>. There's no separate "cancelled" case in ``BackgroundDownloads/Event`` — a cancelled download is reported through ``BackgroundDownloads/onEvent`` as an ordinary `.failed` event, with `NSURLErrorCancelled` as its underlying error, the same way any other failure is. ``BackgroundDownloads/cancel(id:)`` returns `false` when there's nothing to cancel — the download already finished, failed, or never existed under that `id`.

## Pausing and resuming a download

```swift
await BackgroundDownloads.suspend(id: "episode-42")
// ...
await BackgroundDownloads.resume(id: "episode-42")
```

``BackgroundDownloads/suspend(id:)`` holds a running download back until ``BackgroundDownloads/resume(id:)``. Both return `false` when no running download has that `id`. A pause is something you asked for, so it isn't reported through ``BackgroundDownloads/onEvent``: a paused download simply makes no more progress. If the system or the server gives up the connection while it waits, it reconnects when you resume, from where it got to.

## Continuing a download that stopped

A download can stop before it finishes: the network failed for longer than the system keeps trying, or you cancelled it. When some of the file had arrived and the server can say whether the resource is still the same one, `URLSession` keeps what it takes to carry on from there, and you can use it instead of starting over:

```swift
BackgroundDownloads.onEvent = { event in
    if case .failed(let id, _, let error) = event,
       let resumeData = BackgroundDownloads.resumeData(from: error) {
        save(resumeData, for: id)   // it is `Codable`
    }
}

// Later, even after a relaunch:
try await BackgroundDownloadTask(
    id: "episode-42",
    destination: episodesDirectory.appendingPathComponent("episode-42.mp3"),
    resumingFrom: savedResumeData
) {
    BaseURL("api.example.com")
    Path("episodes/42/audio")
}
.result()
```

``BackgroundDownloads/resumeData(from:)`` reads it from the error of a ``BackgroundDownloads/Event/failed(id:destination:error:)`` event, and returns `nil` when there is none (the failure is one that continuing can't fix, nothing of the file had arrived, or the server doesn't support asking for a part). To cancel and get it in one step, use ``BackgroundDownloads/cancelProducingResumeData(id:)``: the download is cancelled either way, and still reported as a `.failed` event.

The content you pass when continuing is the request of the download that stopped, written again. What is asked for comes from the resume data; the content is what the download needs besides that: its trust and client certificate configuration, and the host the latter is bound to.

If the resource changed in the meantime, the system starts the download over instead of continuing it, so what ends up at `destination` is always one version of the file and never a mix of two. Check the size, or use a validator of your own, if you need to know which.

> Note: ``BackgroundDownloadResumeData`` is opaque: it is `URLSession`'s own, in a format that is neither documented nor stable across versions of the system. RequestDL stores nothing; keeping it is yours. It isn't interchangeable with a ``DownloadResumptionPoint``, which belongs to ``DownloadTask`` and ``RequestTask/continuingDownload(from:whenChanged:)`` and works on every platform.

## Trusting a specific server certificate

``TrustRoots``, ``AdditionalTrustRoots``, and ``SecureConnection/verification(_:)`` all work exactly as they do with ``DownloadTask``:

```swift
try await BackgroundDownloadTask(
    id: "episode-42",
    destination: episodesDirectory.appendingPathComponent("episode-42.mp3")
) {
    BaseURL("api.example.com")
    Path("episodes/42/audio")

    SecureConnection {
        TrustRoots(certificateURL)
    }
}
.result()
```

None of these need a Keychain round-trip to survive a relaunch — only the certificate bytes themselves, which travel alongside `id`/`destination` in the scheduled task's own state, the same way.

## Presenting a client certificate (mTLS)

Works too, as long as both ``Certificate`` and ``PrivateKey`` come from a **file path**, not in-memory bytes:

```swift
try await BackgroundDownloadTask(
    id: "episode-42",
    destination: episodesDirectory.appendingPathComponent("episode-42.mp3")
) {
    BaseURL("api.example.com")
    Path("episodes/42/audio")

    SecureConnection {
        Certificates(certificateFileURL.absolutePath(percentEncoded: false))
        PrivateKey(privateKeyFileURL.absolutePath(percentEncoded: false))
    }
}
.result()
```

Only the file path is persisted alongside `id`/`destination` — never the key material itself. The identity is rebuilt from that file via a fresh Keychain round-trip on every challenge, live or after a relaunch alike, the same way it would be for a foreground request. This is exactly why the path has to be stable: a certificate/key backed by in-memory bytes has nothing left to rebuild from once the process that held them is gone. See ``BackgroundDownloadUnsupportedConfigurationError`` for the specific cases that still aren't supported (in-memory bytes, a pre-built certificate, or a password-protected private key).

## What's not supported yet

- **Modifiers and interceptors.** ``BackgroundDownloadTask`` does not conform to ``RequestTask`` — its result doesn't arrive in-process the way every modifier/interceptor assumes.

## Topics

### Scheduling a download

- ``BackgroundDownloadTask``

### Observing and managing downloads

- ``BackgroundDownloads``
- ``BackgroundDownloads/Event``

### Continuing a download that stopped

- ``BackgroundDownloadResumeData``
- ``BackgroundDownloads/resumeData(from:)``
- ``BackgroundDownloads/cancelProducingResumeData(id:)``
- ``BackgroundDownloadTask/init(id:destination:resumingFrom:content:)``

### Errors

- ``BackgroundDownloadUnsupportedConfigurationError``
- ``BackgroundDownloadStatusCodeError``
