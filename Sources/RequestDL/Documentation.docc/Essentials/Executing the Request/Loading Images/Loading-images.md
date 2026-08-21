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
