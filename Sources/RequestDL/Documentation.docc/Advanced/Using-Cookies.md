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

### What the jar does

It follows RFC 6265. A `Set-Cookie` header is stored with the host and path it applies to, replaced when the server sets it again, and removed when it expires or the server deletes it. A request is sent the cookies that match its host, path and scheme, longest path first.

Redirects are part of it: the cookies a redirect sets are in time for the request it leads to, on the same host or another one, which is what login flows rely on.

A request that sets a `Cookie` header itself keeps it, on every hop, and is not given the jar's cookies. The jar still stores what the responses set.

### Public suffixes

Without help, a server could set a cookie for `Domain=co.uk` and have it sent to every site below it. The jar always refuses a `Domain` that is a single label. To refuse multi-label suffixes too, give it a Public Suffix List, which RequestDL does not bundle because it keeps changing:

```swift
let list = try PublicSuffixList(contentsOf: bundledListURL)
let jar = CookieJar(publicSuffixList: list)
```

### What it does not do

- Cookies are not saved to disk.
- `SameSite` is ignored: a client has no notion of the site that made a request.
- Background downloads are not covered, because the system sends those requests itself.
