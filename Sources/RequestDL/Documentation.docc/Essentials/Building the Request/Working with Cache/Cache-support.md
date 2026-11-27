# Caching your responses

Caching requests is crucial for saving costs and unnecessary loading screens. Dive deep into how to use the RequestDL's caching system.

## Overview

Caching requests is crucial for both user experience and reducing unnecessary costs associated with consuming remote APIs.

RequestDL provides two ways to do this: through ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:encryptionKey:)`` or through ``RequestDL/DataCache``.

Depending on the needs of each project, it may be interesting to use both methods, as one of them is completely independent of the request logic.

> Warning: ``RequestDL/DataCache`` does not apply any validation regarding the validity of the cache.

### Property

Configuring and using the cache system directly during the request specification is advantageous because it is a shorter path. Additionally, depending on the ``RequestDL/CacheStrategy`` used, RequestDL checks if the cache is valid at the endpoint, simple as that.

To do this, you need to pay attention to the following points:

1. Specify the ``RequestDL/DataCache/Policy``.
2. Choose the ``RequestDL/CacheStrategy``.
3. Define the storage location with ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:encryptionKey:)``.

Here's an example of how these three points are implemented in practice:

```swift
DataTask {
    BaseURL("apple.com")
        .cachePolicy(.memory)
        .cacheStrategy(.returnCachedDataElseLoad)
        .cache(url: cacheStorageURL)
}
```

Defining the storage location is optional. The default values for memory and disk usage are 2 MB. However, ``RequestDL/DataCache/Policy`` and ``RequestDL/CacheStrategy`` are essential for active caching.

> Important: There are three options to choose where to store the cache: URL, suiteName, or exclusively reserved for the app.

### DataCache

Another way to store the result of a request is by using ``RequestDL/DataCache`` directly. You can even implement your own logic for storing and using RequestDL's default when making the request again.

These are the main usage methods:

@Links(visualStyle: list) {
    - ``RequestDL/DataCache/getCachedData(forKey:policy:)``
    - ``RequestDL/DataCache/setCachedData(_:forKey:)``
    - ``RequestDL/DataCache/remove(forKey:)``
}

> Note: Just like we use methods to specify the storage location in a request specification, the ``RequestDL/DataCache`` initializers are available with the same options.

### How long a response is kept fresh

A stored response is used by ``RequestDL/CacheStrategy/returnCachedDataElseLoad`` only while it is fresh, and what makes it fresh is what the server said:

1. A `max-age` in `Cache-Control` (less the `Age` the response arrived with), or else an `Expires` date. `max-age=0`, or an `Expires` that is not a date, is already stale.
2. Without either, a freshness estimated from the response itself, as browsers do (RFC 9111 §4.2.2): a tenth of the time between its `Last-Modified` and its `Date`, and never more than a day. A resource that changed an hour before it was fetched is kept for six minutes, and one that has not changed in a year is kept for a day.
3. Without a `Last-Modified` to estimate from, it is not fresh at all: the response is stored (its `ETag` and body are still there for ``RequestDL/CacheStrategy/reloadAndValidateCachedData`` and ``RequestDL/CacheStrategy/useCachedDataOnly``), but every ``RequestDL/CacheStrategy/returnCachedDataElseLoad`` request goes to the network.

An error response (`404`, `405`, `410`, `414`, `501`) is stored, and reused, only when it says for how long with a `max-age` or an `Expires`. It is never estimated: a `404` for something that does not exist yet would otherwise outlive its creation.

A stale response is not removed for its age. It stays until a newer response for the URL replaces it, or the disk tier needs the room, so that ``RequestDL/CacheStrategy/useCachedDataOnly`` can still give it to a caller that is offline. The exception is one that must be validated before it is used (`must-revalidate`, or `no-cache`, which a `304` can add): it is not given while stale, and it is kept for a request that revalidates.

A `304 Not Modified` updates the stored response with the `Cache-Control` directives it carries and keeps the ones it does not mention, so one that only says `public` does not take the `max-age` away. A `304` that says `no-store` removes the entry and the request goes to the network; one that says `no-cache` is used for the request that validated it and must be validated again before every later use.

### Large responses and a slow cache

The response is stored while it downloads, not after: each chunk is handed to the caller and, in parallel, to a writer that puts it in the memory and disk tiers. The network is never slowed down for that writer, so the chunks it has not taken yet wait in memory.

That wait has a limit of 16 MiB. If the writer falls more than 16 MiB behind the download, which takes a body larger than that, arriving faster than the cache can write it (a fast connection, or a ``RequestDL/DataCache`` busy with other reads and writes), RequestDL stops caching that response:

- The request is not affected. It succeeds, and the caller receives the whole body.
- What had been written is discarded, never kept as if it were the full response, and a `.warning` is logged ("Response will not be cached").
- The next request for that URL finds no entry and goes to the network, the same as for a response that was never cacheable. There is no error to catch: this is only visible as a cache miss.

Responses that are cacheable but this large are best served by a cache that can keep up, for example one on its own storage URL rather than one shared with a lot of other traffic. The 16 MiB bound is not configurable.

### Responses that cannot be proven complete

A cache entry that is cut short is worse than no entry: it is served for as long as it stays fresh, and nothing about it says it is incomplete. So RequestDL only stores a response it can tell arrived whole.

On the `.nio` executors that holds for the two kinds of body that say where they end. A body with a `Content-Length` is checked against it, and a chunked body (`Transfer-Encoding: chunked`, no `Content-Length`) ends with a terminating zero-length chunk: a connection that closes before it fails the request, and a failed response is never stored. Chunked responses are cached as usual.

The exception is a body that is delimited by the connection closing: an HTTP/1.0 server, or a proxy, that answers with neither a `Content-Length` nor a `Transfer-Encoding`. The end of such a body is the end of the connection, and a connection that drops half way ends it just the same, so there is nothing that says it was cut. RequestDL treats it as complete and stores it: `.nio` has no way to tell, and `.urlSession` only holds back a response that shows a `Transfer-Encoding`. This is a limit of HTTP/1.x itself, not something the cache can detect. If a server you depend on behaves like this, the completeness probe does not help (it only runs for chunked responses): keep such responses out of the cache with ``RequestDL/Property/cachePolicy(_:)``, or have the server send a `Content-Length`.

If you need these responses cached, you have two ways:

- Pin the request to `.nio` with ``Session/requiredExecutor(_:)``. This is the cheapest, and the one that also keeps the failure visible to the caller.
- Turn on the completeness probe with ``RequestDL/Property/cacheCompletenessProbe(_:)``, which asks the server whether it had more bytes before the response is stored.

#### The completeness probe

```swift
DataTask {
    BaseURL("downloads.example.com")
        .cachePolicy(.disk)
        .cacheStrategy(.returnCachedDataElseLoad)
        .cacheCompletenessProbe()
}
```

Off by default. When it is on, and only for a `.urlSession` response that would otherwise be left out (no `Content-Length`, with a `Transfer-Encoding`, which is all CFNetwork shows of a chunked body; an HTTP/2 response without `Content-Length` has neither and is stored without it), the cache writer sends **one extra request** once the body has been received and before it stores it: the same `GET`, with `Range: bytes=<n>-<n>` (`n` being the number of bytes received) and, when the response carried a strong `ETag` or a `Last-Modified`, `If-Range` with it. The caller already has its response by then, so this does not delay it. The extra request is part of the cost of every write, goes out through the same session (credentials, proxies and certificates included), and gives up after 30 seconds.

What the answer says:

| Answer | Meaning | Stored |
| --- | --- | --- |
| `416` with `Content-Range: bytes */<n>` | There is no byte after the `n` that were received. | Yes |
| `206` | There is a byte after them: the body was cut. | No |
| `200`, any other status, a `416` for another length, a failure or no answer in time | The server does not do ranges, or says something else. | No |

The probe only runs when the response advertised `Accept-Ranges: bytes`, which keeps a server that ignores `Range` from answering the probe with the whole body again. A server that answers with the whole body anyway, because the `If-Range` no longer matches, is not read past its headers: the probe stops at the status line and the headers, and cancels the request. It does not decide, and nothing is stored, when:

- the response has a `Content-Encoding`. `.urlSession` hands over the decoded body, and a byte range counts the encoded one, so `n` would point somewhere else;
- the server does not support ranges for a body that it sends chunked. That is common for responses generated on the fly, and for those the answer is not in the probe's hands: pin them to `.nio`;
- the resource changed between the two requests and the response had no validator to tell it. Both ends can then match by chance. A strong `ETag` removes that case.

> Important: The probe says the body is as long as the server says it is. It does not check the bytes themselves.

### Responses to requests with credentials

A cache is keyed by URL, and a ``RequestDL/DataCache`` is often one store for the whole process, so a response fetched with one account's credentials must not be given to another. A request that sends `Authorization`, `Cookie` or `Proxy-Authorization` (a `Cookie` the session's cookie jar adds counts) has its response stored with a SHA-256 digest of each of the three, never their values, and the response is only served to a request that sends the same: not to another account, and not to a request with none. A response stored for a request with none of them is public and is served to every request.

That is right for a credential that does not change, and wrong for one that does. An OAuth token that is refreshed, or a session cookie that the server re-issues with every response, is a new value for the same account, so the stored response is never found again after the refresh. Declare the account yourself with ``RequestDL/CacheIdentity`` and the cache compares that instead:

```swift
DataTask {
    BaseURL("https://api.example.com")
    Path("/me/orders")
    Authorization(.bearer, token: session.accessToken)
    CacheIdentity(session.userID)
}
.cachePolicy(.all)
.cacheStrategy(.returnCachedDataElseLoad)
```

With an identity:

- The response is stored with a digest of the identity and none of the credentials, and is served to a request that declares the same identity, whatever `Authorization` or `Cookie` it sends. The identity itself is not written to the disk.
- It is not served to another identity, nor to a request that declares none; a response stored with no identity (for credentials, or a public one) is not an identity's own, so only the public one is served to it.
- A `Vary` of `Authorization`, `Cookie` or `Proxy-Authorization` is satisfied by the identity. Any other field in `Vary` is compared as usual.
- An empty identity, or one that is only whitespace, is ignored: the request is cached by its credentials.

The identity is a claim by the app: the cache does not check that the credentials belong to it, and two accounts given the same identity share what they cache. It is not part of the cache key, which stays the URL, and nothing is sent to the server. Records written before ``RequestDL/CacheIdentity`` existed keep matching as they did.

### Encrypting the disk tier

By default, cached responses are written to disk as plaintext. If the cached content is sensitive — auth-protected API responses, personal data, anything you wouldn't want readable by something else with access to the device's file system — set an ``RequestDL/DataCache/EncryptionKey`` so RequestDL encrypts the disk tier at rest with AES-GCM.

A few things to know before turning it on:

1. **Only the disk tier is encrypted.** The in-memory tier (``RequestDL/DataCache/Policy/memory``) is never encrypted — it only ever exists as bytes in your process' own memory, out of scope for this feature. If that matters for your threat model, restrict the policy to ``RequestDL/DataCache/Policy/disk`` for the data you're encrypting.
2. **RequestDL does not manage the key itself.** Generating, rotating, and securely storing the key bytes (Keychain, a KMS, whatever fits your app) is your responsibility. RequestDL only carries the key across the boundary and uses it to seal/open cache files. The key has to be at least 16 bytes long, and 32 is recommended (AES-256-GCM): a key of 16, 24 or 32 bytes is used as it is, and a longer one of any other length is run through HKDF-SHA256. A shorter key, an empty one included (what a Keychain read that found nothing gives), would be as good as public once stretched to a key, so ``RequestDL/DataCache/EncryptionKey`` does not make a usable one of it: a cache that has it writes nothing to the disk tier and finds nothing in it, instead of looking encrypted while anyone could read it. The memory tier keeps working.
3. **The key stays set until you change it.** `.cache(...)`'s `encryptionKey` parameter and ``RequestDL/DataCache/encryptionKey`` write to the same shared storage for a given directory/suite/URL. Passing a key sets it; passing `nil` to `.cache(...)` leaves whatever key that storage already has, so it does not turn encryption off. To stop encrypting, set ``RequestDL/DataCache/encryptionKey`` to `nil` on the cache itself. A storage that has no key reads ciphertext it cannot open, which — same as a wrong key — is treated as a plain cache miss, so set the key before the first request that reads or writes the directory.
4. **The names of the entries do not say what was fetched, but they say when.** What is encrypted is the body and the response record (status, headers). Each entry lives in a directory named after the date of the response and an HMAC-SHA256 of the URL, made with a key derived from yours (not your key itself), so the URL, its query string included, cannot be read from the cache directory or from a backup of it. The same URL gets the same part of the name under the same key, and another key gives other names. What stays visible is the date of each response, how many entries there are, how big their files are, and that two of them are for the same URL (not which). A cache with no key keeps naming its entries after the URL, in base64 (or a SHA-256 of it when it is long).

   Changing the key, or turning it off, makes the entries of the earlier one a miss, as a wrong key always did: they are evicted with the rest as the disk tier needs room. Entries written before names were hidden (under a key or without one) are no longer found by a cache that has a key, and are removed the next time it makes room (the same pass that evicts), so that the URLs in their names do not stay readable on disk. A cache with no key never removes an entry for how it is named.

#### Generating the key

Where the key bytes come from depends on who owns them. Three common cases:

**Generated on-device, if nothing else needs to know it.** Generate 32 random bytes for AES-256-GCM and persist them somewhere durable (Keychain, for example) — this is the simplest option when the key only ever has to make sense to this app:

```swift
import Crypto

// Once, e.g. at first launch — store the raw bytes in the Keychain from here on.
let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
let encryptionKey = DataCache.EncryptionKey(keyData)
```

**Derived from a secret issued elsewhere** — your backend, a KMS, anything that hands you bytes (or a UUID, a hex/base64 string — whatever encoding it arrives in, decode it to raw bytes first) that already carry real entropy. Don't hand that value to ``RequestDL/DataCache/EncryptionKey`` as-is: run it through HKDF (RFC 5869) instead. HKDF normalizes whatever length it arrives in to the 256 bits AES-256-GCM wants, and — via the `info` parameter — domain-separates the derived key from any other use of that same secret elsewhere in your system, so the two derived keys stay cryptographically independent even though they share a source:

```swift
import Crypto

// `externalSecret` is whatever your backend/KMS handed you, decoded to its raw bytes.
let inputKeyMaterial = SymmetricKey(data: externalSecret)

let derivedKey = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: inputKeyMaterial,
    info: Data("com.yourapp.cache-encryption".utf8),
    outputByteCount: 32
)

let encryptionKey = DataCache.EncryptionKey(derivedKey)
```

> Important: HKDF only makes sense when the input already has real entropy behind it — a randomly generated token, a KMS-derived secret, a UUID. It does nothing to slow an attacker down, so it's the wrong tool for something a person could type or guess.

**Derived from a user-supplied password or PIN.** Don't feed that straight into HKDF — low-entropy input needs a deliberately slow, memory-hard KDF (PBKDF2, scrypt, Argon2) so that guessing it is expensive, which RFC 5869 hashing does not provide. swift-crypto doesn't ship one; reach for a platform API (`CommonCrypto`'s `CCKeyDerivationPBKDF` on Apple platforms) or a dedicated package on whatever platforms you support, and treat that step as separate from what's described here.

On every request that reads or writes an encrypted cache, pass the resulting key in:

```swift
DataTask {
    BaseURL("api.example.com")
        .path("/account")
        .cachePolicy(.disk)
        .cacheStrategy(.returnCachedDataElseLoad)
        .cache(encryptionKey: encryptionKey)
}
```

The same key works with ``RequestDL/DataCache`` directly — set it once on the instance you're using, and it applies to every subsequent read/write through that instance:

```swift
let cache = DataCache(url: cacheStorageURL)
cache.encryptionKey = encryptionKey
```

> Important: A decrypt failure — wrong key, a key that was rotated, or a file that's been corrupted or tampered with — is always treated as a cache miss, never a crash. The entry is silently discarded and re-fetched, then re-encrypted under whatever key is set at that point. This means rotating keys doesn't require migrating old entries: they simply stop being read and get replaced naturally as requests re-run. If you suspect a key was compromised, call ``RequestDL/DataCache/removeAll()`` to drop the old ciphertext outright rather than leaving it on disk.

> Note: On Apple platforms, encryption is complementary to, not a replacement for, the OS's own Data Protection classes — see ``RequestDL/DataCache/fileProtection``. Encryption keeps the content unreadable without your key regardless of platform; `fileProtection` additionally ties readability to the device being unlocked.

## Topics

### The caching system

- ``RequestDL/DataCache``
- ``RequestDL/CachedData``
- ``RequestDL/EmptyCachedDataError``

### Defining the strategy

- ``RequestDL/CacheStrategy``
- ``RequestDL/Property/cacheStrategy(_:)``

### Caching responses without a length

- ``RequestDL/Property/cacheCompletenessProbe(_:)``

### Defining the policy

- ``RequestDL/DataCache/Policy``
- ``RequestDL/DataCache/Policy/Set``
- ``RequestDL/Property/cachePolicy(_:)``

### Telling accounts apart

- ``RequestDL/CacheIdentity``

### Encrypting the disk tier

- ``RequestDL/DataCache/EncryptionKey``
- ``RequestDL/DataCache/encryptionKey``
- ``RequestDL/DataCache/fileProtection``

### Initializing the cache  

- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:encryptionKey:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:suiteName:encryptionKey:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:encryptionKey:)``
