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

The jar is yours: keep it for as long as the cookies should live, share it between sessions that should share a login, and call ``CookieJar/removeAll()`` to sign out. To look at what it holds, change it, watch it, or keep it across launches, see <doc:Using-Cookies#Managing-the-cookies> and <doc:Using-Cookies#Keeping-a-jar-across-launches>. Two sessions with different jars never see each other's cookies, even when they share a connection.

A response fetched with cookies is given back from a ``DataCache`` only to a request that sends all of the cookies it was fetched with, so a cookie the jar gains later (an analytics id, say) does not make the stored response unreachable, which would break `.useCachedDataOnly`. A request that sends a different value for one of them, or none, still does not get it, so a session cookie that the server renews with a new value on every response keeps missing the cache.

The jar does not make a ``DataCache`` private to it. A response kept in a cache shared by several sessions is still kept with the `Set-Cookie` it came with, and a later request served from it does not feed that header into its own jar. A response fetched through a redirect that was sent cookies the first request did not carry is never stored in the cache, because the cache could not tell whose it is.

### What the jar does

It follows RFC 6265. A `Set-Cookie` header is stored with the host and path it applies to, replaced when the server sets it again, and removed when it expires or the server deletes it. A request is sent the cookies that match its host, path and scheme, longest path first.

Redirects are part of it: the cookies a redirect sets are in time for the request it leads to, on the same host or another one, which is what login flows rely on.

A request that sets a `Cookie` header itself keeps it on every hop to the same origin, and is not given the jar's cookies. Like any credential you set by hand, it is left behind when a redirect goes to another origin, and the jar does not fill that hop in its place. The jar still stores what the responses set.

### Public suffixes

Without help, a server could set a cookie for `Domain=co.uk` and have it sent to every site below it. The jar always refuses a `Domain` that is a single label, with a list or without one. To refuse multi-label suffixes too, give it a Public Suffix List, which RequestDL does not bundle because it keeps changing.

The jar has **no list by default**, and that matters beyond country suffixes. Platforms that host many unrelated sites under one name are public suffixes too, and without a list one tenant can plant a cookie on all the others. `attacker.github.io` can answer with `Set-Cookie: sid=attacker; Domain=github.io`, and the jar then sends that cookie to every other `*.github.io` site it visits (session fixation, or a cookie bomb that breaks the others). The same holds for `*.herokuapp.com`, `*.vercel.app`, `*.netlify.app`, `*.pages.dev`, `*.azurewebsites.net`, S3 buckets under `*.s3.amazonaws.com`, and every other name in the private section of the list. If the jar talks to hosts you do not control, give it a list:

```swift
let list = try PublicSuffixList(contentsOf: bundledListURL)
let jar = CookieJar(publicSuffixList: list)
```

Parse the list once and reuse it. A file that is not a list, such as the HTML or JSON error page a failed download saved in its place, is refused with a ``PublicSuffixListError`` instead of being taken for a list that protects from nothing. A plain-text body made only of words cannot be told from a list of one-label names, so bundle the list, or check the status of the download. Names are compared in their Punycode form, so a list written in Unicode covers a host in either spelling.

### Limits

A domain holds at most 50 cookies and a jar at most 3000, and when one of those limits is reached the least recently used cookies go first. A single response may set at most 50: the first 50 `Set-Cookie` headers are read and the rest are ignored. The limit is per response, and every hop of a redirect is a response of its own.

Those limits count cookies, not bytes, and a cookie may have up to 4096, so a server could still set 50 large cookies that make every later request to its domain too big for any server to accept. The `Cookie` header a request is sent therefore has at most 8000 bytes (under the 8 KB a header line may have by default in common servers, such as nginx, Apache and Tomcat). When the cookies that match do not fit, the ones with the shortest paths are left out and, among equal paths, the oldest, so a cookie that was just set (a login) is not the one that goes; and none that is less specific than the first that does not fit is sent. A cookie that is left out stays in the jar and is not counted as used. ``CookieJar/cookies(for:)`` lists what would be sent, so it leaves them out too.

### Managing the cookies

A jar can be read and changed while requests use it. A cookie is a ``CookieJar/Cookie``, a value with the name, value, domain, whether it is host-only, path, `Secure` and `HttpOnly` flags, expiry (`nil` for a session cookie) and creation time.

```swift
let all = jar.cookies
let toSend = jar.cookies(for: URL(string: "https://api.example.com/v1/me")!)
```

``CookieJar/cookies(for:)`` is what a request to that URL would carry, in the order it would carry it. Both are copies, and reading them does not count as using the cookies, so it never changes which one the jar evicts first.

To add a cookie, insert it. It replaces the one with the same name, domain and path, and a cookie that has already expired deletes it:

```swift
try jar.insert(
    CookieJar.Cookie(
        name: "session",
        value: token,
        domain: "api.example.com",
        path: "/",
        secure: true,
        expires: Date(timeIntervalSinceNow: 3600)
    )
)
```

Insertion refuses what a received cookie would be refused for, and throws a ``CookieJarError`` that says which part: control characters, a non-ASCII character in the name or value (RFC 6265 allows only ASCII, and `URLSession` cuts the whole `Cookie` header at the first character it cannot encode, so one such cookie would cost the others after it; a received cookie with one is dropped the same way), a name and value over 4096 bytes, the `__Secure-` and `__Host-` prefix rules, and, for a cookie that is not host-only, a single-label domain or a public suffix of the jar's list. Because the cookie has no response to come from, three checks are not made: that its domain covers the host that sent it (the domain you give is its origin), that a `Secure` cookie arrived over HTTPS (it is accepted, and still only sent over HTTPS), and the limit of 50 per response. It is stricter than a response in one way: a `;` in a name or value, and a path that does not start with `/`, are refused, since a value like `x; admin=1` would otherwise add a second cookie to the `Cookie` header.

To remove cookies:

```swift
jar.remove(name: "session", domain: "api.example.com", path: "/")
jar.removeAll(forHost: "api.example.com")
jar.removeAll(forHost: "example.com", includingSubdomains: true)
jar.removeAll()
```

``CookieJar/removeAll(forHost:includingSubdomains:)`` removes the cookies a request to that host would match, whatever their path: a cookie set for `example.com` goes with `api.example.com`. With `includingSubdomains` it also removes the cookies of the hosts below it.

Each call is atomic, but a read followed by a change is two calls, and a response can be stored between them.

On Apple platforms, cookies convert to and from Foundation's `HTTPCookie` with `CookieJar.Cookie(_:)` and ``CookieJar/Cookie/httpCookie``, to move them from `HTTPCookieStorage` or a web view's cookie store. `HTTPCookie` has no creation time, and a host-only cookie is one whose domain has no leading dot. A converted cookie is still checked when you insert it.

### Observing changes

``CookieJar/changes`` is a stream that gets an element each time what the jar holds changes: a response set or deleted a cookie, you inserted, removed or restored some, or a limit evicted one. The usual use is to save the jar when something changed:

```swift
let changes = jar.changes

Task {
    for await _ in changes {
        try save(jar.snapshot())
    }
}
```

An element says that the jar changed, not what changed or how many times. Changes that happen while you are busy are merged into one, so read the jar again when you get an element and you see all of them. The element carries no cookie, so there is nothing in it to leak.

Every read of `changes` is a new stream, registered when you read it, not when you start iterating: take it before you read the jar, so a change in between is not missed. It ends when the jar is deallocated, and the jar stops tracking it when you cancel the task.

A cookie expiring is not a change (nothing happens at that instant: it stops being listed), nor is a cookie being sent, a response that sets a cookie with the same value, flags and `Expires` it already has, or clearing an empty jar.

A response that renews a `Max-Age` is a change: the expiry it gives is later every time, and a snapshot would have to save it. A server with sliding sessions (`Max-Age=3600` on every response) therefore gives you an element per response, so wait a moment before you write to disk or to the Keychain, and merge what arrives in the meantime.

### Keeping a jar across launches

A jar can be saved as a ``CookieJar/Snapshot``, a `Codable` value, and restored from it. RequestDL stores it nowhere: you encode it, and keep it where you decide.

```swift
// Saving
let data = try JSONEncoder().encode(jar.snapshot())
try keychain.store(data, for: "cookies")

// Next launch
let snapshot = try JSONDecoder().decode(CookieJar.Snapshot.self, from: keychain.load("cookies"))
let jar = CookieJar(restoring: snapshot, publicSuffixList: list)
```

Dates are written as seconds since 1970 whatever the encoder's date strategy, and the encoded form has a version: one written by a newer RequestDL fails to decode instead of being half read.

Restoring is not inserting. Each cookie is checked as an inserted one is, against the list of the jar that receives it, and one that fails is skipped and counted in the result of ``CookieJar/restore(_:)``: an edited snapshot cannot bring in a `Domain=co.uk` cookie. Expired cookies are skipped rather than taken for a deletion, a cookie the jar already holds wins over the saved one (call ``CookieJar/removeAll()`` first for the other behavior), and at most 3000 cookies of a snapshot are considered.

#### Keeping it safe

- **A snapshot is a set of credentials.** Whoever reads it is signed in as the user until the servers say otherwise. Treat it like a password or a refresh token: not in `UserDefaults`, a plain file, a backup, a log, a crash report or the pasteboard. On Apple platforms keep it in the Keychain, with an accessibility class such as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so it is neither backed up nor moved to another device, or encrypt it with a key that is. Elsewhere, a file only the app's user can read, or the platform's secret store.
- **Session cookies are left out by default.** A server hands out a session cookie to be dropped when the session ends. Passing `includingSessionCookies: true` makes it last as long as the server's own timeout, and breaks a server that relies on a session ending. Include them only when you control the server, and prefer signing in again.
- **A snapshot has to be trusted.** A restored cookie is checked for what makes a cookie dangerous, not for where it came from, so someone who can change the saved data can plant a cookie for any domain. Keep it where it cannot be changed, or authenticate it.
- `HttpOnly` is saved. It tells a browser's scripts to keep out; at rest it protects nothing.
- Cookie values are kept in memory like any header, and are not erased.

A ``CookieJar/Cookie`` and a ``CookieJar/Snapshot`` print without their values (`<redacted>`), and so does every ``CookieJarError``, so a stray `print` does not leak a session. Encoding writes them, because that is what it is for. RequestDL does not log a `Cookie` header either.

### What it does not do

- Cookies are not saved by RequestDL: a snapshot is yours to keep, and to protect.
- `SameSite` is ignored: a client has no notion of the site that made a request.
- A comma never separates cookies, as RFC 6265 says: `Set-Cookie: a=1,b=2` is one cookie, `a`, on every executor. The one case `.urlSession` cannot get right is a value that holds a comma, a space and something that looks like `name=` (`a=1, b=2` in a single header): the system joins repeated `Set-Cookie` headers with exactly that, and the jar cannot tell the two apart, so there it stores two cookies where the other executors store one.
- Background downloads are not covered, because the system sends those requests itself.
