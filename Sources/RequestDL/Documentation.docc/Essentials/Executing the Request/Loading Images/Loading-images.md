# Loading images

Load and display images directly from a URL or a request, using RequestDL's own pipeline and cache — for SwiftUI, UIKit, AppKit, and watchOS.

## Overview

Loading an image is just another way of consuming a request's result: fetch the bytes, decode them, and show whatever came back. RequestDL's image loading APIs are built as a thin layer on top of the same pieces used everywhere else in the package — ``RequestDL/DataTask``, ``RequestDL/DataCache``, ``RequestDL/Property/cachePolicy(_:)``, ``RequestDL/Property/cacheStrategy(_:)`` — so anything you already know about caching and configuring a request applies here too.

Four entry points share one engine, ``RequestDL/RDLImageLoader``:

- ``RequestDL/RDLImage``, a SwiftUI view that mirrors `AsyncImage`.
- `UIImageView.rdl`, on iOS and tvOS.
- `NSImageView.rdl`, on macOS.
- `WKInterfaceImage.rdl`, on watchOS.

> Important: Concurrent loads that share the same identifier are deduplicated by ``RequestDL/RDLImageLoader`` — only one request is in flight at a time per identifier, and every caller waiting on it gets the same result. This is separate from, and on top of, RequestDL's own response cache: the dedupe layer is what makes many views asking for the same image *at once* cheap, while the cache is what makes asking for it again *later* cheap.

### RDLImage

`RDLImage` mirrors `AsyncImage`'s API — the same URL-based initializers, `AsyncImagePhase`-like driven rendering, and content/placeholder convenience:

```swift
RDLImage(url: url) { image in
    image.resizable()
} placeholder: {
    ProgressView()
}

RDLImage(url: url) { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let image):
        image.resizable()
    case .failure:
        Image(systemName: "photo")
    @unknown default:
        EmptyView()
    }
}
```

When the loader has the image in memory (see below), the view's first phase is already `.success`, in the frame it is created in, instead of `.empty`; `RDLImage(url:)` then makes no request unless you pass `refreshing: true`, and `RDLImage(id:task:)` still does and replaces the copy.

Use the ``RequestDL/RDLImage/init(id:scale:transaction:loader:task:content:)`` initializer when the request needs more than a URL — custom headers, authentication, a specific ``RequestDL/Property/cachePolicy(_:)``, and so on — by building it the same way a ``RequestDL/DataTask`` is built:

```swift
RDLImage(
    id: "avatar",
    task: DataTask {
        BaseURL("cdn.example.com")
        Path("avatar.png")
        CustomHeader(name: "Authorization", value: token)
    }
) { phase in
    // ...
}
```

Any ``RequestDL/RequestTask`` producing a ``RequestDL/TaskResult`` of `Data` works here, so a ``RequestDL/MockedTask`` also drops in directly — handy for SwiftUI previews and tests that shouldn't hit the network.

> Important: `id` identifies the request for both restarting the load — when it changes, the current load is cancelled and a new one begins, the same way `AsyncImage` reacts to a new `url` — and deduplicating concurrent loads in ``RequestDL/RDLImageLoader``. It can't be derived automatically from an arbitrary ``RequestDL/RequestTask``, so you supply it explicitly, typically the URL or endpoint the request resolves to.

### UIImageView, NSImageView, and WKInterfaceImage

The same two entry points — a plain `URL` or an already-built ``RequestDL/RequestTask`` — are available on `UIImageView`, `NSImageView`, and `WKInterfaceImage`, through the `.rdl` namespace so they don't add members directly to those types:

```swift
imageView.rdl.setImage(with: url, placeholder: UIImage(named: "placeholder"))

imageView.rdl.setImage(
    id: "avatar",
    task: DataTask {
        BaseURL("cdn.example.com")
        Path("avatar.png")
        CustomHeader(name: "Authorization", value: token)
    }
) { result in
    switch result {
    case .success(let image):
        // ...
    case .failure(let error):
        // ...
    }
}
```

Every `setImage` call cancels whatever load is already in flight on that image view first, which is what makes it safe to call from `tableView(_:cellForRowAt:)`, `collectionView(_:cellForItemAt:)`, or a `WKInterfaceTable` row controller — a cell recycled mid-load never has a stale image land on it after the fact. Call `.rdl.cancel()` directly (for instance, from `prepareForReuse()`) to stop a load without starting another.

Starting a `setImage` also replaces whatever the view is showing right away: with `placeholder` when you pass one, and with nothing when you don't. This is what keeps a reused cell honest — a recycled cell would otherwise keep the previous row's image on screen, the wrong picture, until the new one arrives.

When the loader already has the image you ask for, the view gets that image instead, in the same turn: not the placeholder, and not an empty frame. ``RDLImageLoader`` keeps the images it has loaded decoded in memory (64 MB by default, counted in pixels, emptied by the system when memory runs low), and each one is good for 5 minutes from when it was loaded. What happens after that depends on how you asked for the image:

- **By URL** (`setImage(with:)`, `RDLImage(url:)`): a valid copy is the answer, and **no request is made**, with no disk read and no decode. Your `completion` is called at once. The URL is all that identifies the request, so the copy can only be wrong by its age, which the time to live bounds. Pass `refreshing: true` to `setImage(with:)` to make the request anyway (the copy stays on screen until the new image arrives), or pass `refreshing: true` to `RDLImage(url:)`, which does the same: its first phase is the copy and the request's result replaces it. ``RDLImageLoader/removeCachedImage(url:)`` forgets the copy for every view instead.
- **By task** (`setImage(id:task:)`, `RDLImage(id:task:)`): the copy is only shown first, and the request **still runs**, with its cache policy, headers and credentials, and replaces it. You control those, and the key is the `id` you chose, so a copy made for another account or another policy is never the final answer. If that request fails, the copy stays.

The copy is keyed by the URL, or by the `id`, and is only written when a load finishes with success: a failed load leaves it as it was. ``RDLImageLoader/load(url:)`` and ``RDLImageLoader/load(id:task:)`` themselves never read it: they always run the request.

Use the loader to manage it: ``RDLImageLoader/removeCachedImage(id:)``, ``RDLImageLoader/removeCachedImage(url:)`` and ``RDLImageLoader/removeAllCachedImages()`` forget images (for example after the user changes their avatar; a load that was already running when you call them does not put its result back in memory), ``RDLImageLoader/memoryCacheLimit`` (or `init(dataCache:memoryCacheLimit:memoryCacheTimeToLive:)`) changes the size, with `0` turning the cache off, and ``RDLImageLoader/memoryCacheTimeToLive`` changes how long an image is good for (`nil` for as long as it stays in memory). A cache that is off, or an image that expired, is a miss, and the view starts empty or with its placeholder as it did before. On `WKInterfaceImage` an image in memory is also set at once; what it is showing cannot be read, so `placeholder` is still always ignored with `keepsCurrentImageWhileLoading`.

> Important: Before this default, `setImage` left the current image untouched when `placeholder` was `nil`. If you relied on that, pass `keepsCurrentImageWhileLoading: true`.

When the view reloads the *same* content — refreshing an avatar, say — keeping the old image on screen is better than flashing a placeholder, so opt in:

```swift
avatarView.rdl.setImage(with: avatarURL, keepsCurrentImageWhileLoading: true)
```

With `keepsCurrentImageWhileLoading: true` a view that is showing an image isn't touched until the new image arrives, and `placeholder` is ignored for it. A view that shows nothing yet (a freshly created cell) still gets the `placeholder`. On `WKInterfaceImage`, which can't be read, `placeholder` is always ignored.

> Note: `WKInterfaceImage` doesn't expose a way to read the image back — `WKInterfaceObject` types are one-way proxies to a system-rendered element — so use the `completion` handler if you need to react to the result there.

### RDLImageLoader

``RequestDL/RDLImageLoader`` is the engine behind all four entry points above, and you can use it directly:

```swift
let image = try await RDLImageLoader.shared.load(url: url)
```

``RequestDL/RDLImageLoader/shared`` is what every entry point uses by default, so unrelated call sites requesting the same image still dedupe against each other. Create your own instance — every initializer above accepts a `loader:` parameter — when you want independent dedupe bookkeeping, for instance to isolate a screen's previews from the rest of the app.

## Topics

### The shared engine

- ``RequestDL/RDLImageLoader``
- ``RequestDL/PlatformImage``
- ``RequestDL/RDLImageDecodingError``

### SwiftUI

- ``RequestDL/RDLImage``
- ``RequestDL/RDLImagePhase``

### UIKit, AppKit, and WatchKit

- ``RequestDL/RDLCompatible``
- ``RequestDL/RDLWrapper``
