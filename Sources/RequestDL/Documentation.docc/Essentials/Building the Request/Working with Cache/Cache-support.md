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

### Encrypting the disk tier

By default, cached responses are written to disk as plaintext. If the cached content is sensitive — auth-protected API responses, personal data, anything you wouldn't want readable by something else with access to the device's file system — set an ``RequestDL/DataCache/EncryptionKey`` so RequestDL encrypts the disk tier at rest with AES-GCM.

A few things to know before turning it on:

1. **Only the disk tier is encrypted.** The in-memory tier (``RequestDL/DataCache/Policy/memory``) is never encrypted — it only ever exists as bytes in your process' own memory, out of scope for this feature. If that matters for your threat model, restrict the policy to ``RequestDL/DataCache/Policy/disk`` for the data you're encrypting.
2. **RequestDL does not manage the key itself.** Generating, rotating, and securely storing the key bytes (Keychain, a KMS, whatever fits your app) is your responsibility. RequestDL only carries the key across the boundary and uses it to seal/open cache files.
3. **The key must be supplied on every call that touches that cache directory**, not just once. `.cache(...)`'s `encryptionKey` parameter and ``RequestDL/DataCache/encryptionKey`` write to the same shared storage for a given directory/suite/URL — including with `nil`. Passing the key on the request that writes an entry but omitting it on the request that reads it back doesn't leave the disk tier encrypted with the old key; it clears the key first, and the read then sees ciphertext with no key to open it, which — same as a wrong key — is treated as a plain cache miss.

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

### Defining the policy

- ``RequestDL/DataCache/Policy``
- ``RequestDL/DataCache/Policy/Set``
- ``RequestDL/Property/cachePolicy(_:)``

### Encrypting the disk tier

- ``RequestDL/DataCache/EncryptionKey``
- ``RequestDL/DataCache/encryptionKey``
- ``RequestDL/DataCache/fileProtection``

### Initializing the cache  

- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:encryptionKey:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:suiteName:encryptionKey:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:encryptionKey:)``
