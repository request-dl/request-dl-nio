# Using Cookies

Keep the cookies a server sets and send them back, across requests and through redirects.

## Overview

A session has no cookies unless you give it a ``CookieJar``. Nothing is stored and no `Cookie` header is added for a request whose session has no jar, on every executor.

```swift
let jar = CookieJar()

struct MyAppConfiguration: Property {
    let jar: CookieJar

    var body: some Property {
        Session("my-app")
            .cookieJar(jar)
    }
}
```

The jar is yours: keep it for as long as the cookies should live, share it between sessions that should share a login, and call ``CookieJar/removeAll()`` to sign out. Two sessions with different jars never see each other's cookies, even when they share a connection.

The jar does not make a ``DataCache`` private to it. A response kept in a cache shared by several sessions is still kept with the `Set-Cookie` it came with, and a later request served from it does not feed that header into its own jar. A response fetched through a redirect that was sent cookies the first request did not carry is never stored in the cache, because the cache could not tell whose it is.

### What the jar does

It follows RFC 6265. A `Set-Cookie` header is stored with the host and path it applies to, replaced when the server sets it again, and removed when it expires or the server deletes it. A request is sent the cookies that match its host, path and scheme, longest path first.

Redirects are part of it: the cookies a redirect sets are in time for the request it leads to, on the same host or another one, which is what login flows rely on.

A request that sets a `Cookie` header itself keeps it on every hop to the same origin, and is not given the jar's cookies. Like any credential you set by hand, it is left behind when a redirect goes to another origin, and the jar does not fill that hop in its place. The jar still stores what the responses set.

### Public suffixes

Without help, a server could set a cookie for `Domain=co.uk` and have it sent to every site below it. The jar always refuses a `Domain` that is a single label, with a list or without one. To refuse multi-label suffixes too, give it a Public Suffix List, which RequestDL does not bundle because it keeps changing:

```swift
let list = try PublicSuffixList(contentsOf: bundledListURL)
let jar = CookieJar(publicSuffixList: list)
```

### Limits

A response may set at most 50 cookies, a domain holds at most 50, and a jar at most 3000. When a limit is reached the least recently used cookies go first.

### What it does not do

- Cookies are not saved to disk.
- `SameSite` is ignored: a client has no notion of the site that made a request.
- Background downloads are not covered, because the system sends those requests itself.
