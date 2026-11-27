# Disabling the NIOTransport Trait

Build RequestDL without SwiftNIO, AsyncHTTPClient, or NIOSSL, running entirely over `URLSession`.

## Overview

RequestDL depends on AsyncHTTPClient, SwiftNIO, and NIOSSL by default, through a Swift Package Manager trait named `NIOTransport`. That trait is what backs the ``Session/Executor/nioTransportServices``/`.nio` executors, plus NIOFileSystem-based disk I/O and the built-in gzip/deflate compression for the request body.

Disabling `NIOTransport` drops that whole dependency subgraph from the build. RequestDL keeps working, over ``Session/Executor/urlSession`` only: every part of the package that would otherwise reach for NIO falls back to a portable mirror that doesn't need it to compile or run.

### Why you'd want this

Without `NIOTransport`, a project that links RequestDL pulls in no AsyncHTTPClient, SwiftNIO, or NIOSSL sources at all: fewer dependencies to fetch, less code to compile, a smaller binary. Requests still run exactly as before, over `.urlSession`, whether or not you pin the executor explicitly, since it's the only one left.

### Platforms

`NIOTransport`-off builds are Darwin only. `.urlSession`'s whole implementation is itself Darwin-exclusive, a pre-existing decision unrelated to this trait. Disabling `NIOTransport` on any other platform leaves no executor at all, and the package won't build.

## Disabling the trait

If you're building RequestDL itself, or a project that depends on it directly, pass `--disable-default-traits` on the command line:

```bash
swift build --disable-default-traits --target RequestDL
```

If your own package depends on RequestDL, disable its default traits from your `Package.swift`:

```swift
.package(
    url: "https://github.com/request-dl/request-dl-nio.git",
    from: "4.0.0",
    traits: []
)
```

## What still works

- Every ``Property`` and header type: none of them touch NIO directly.
- ``SecureConnection``, ``Certificates``, ``PrivateKey``, mTLS and PSK authentication: backed by the same portable types either way, so behavior over `.urlSession` doesn't change.
- ``GzipAlgorithm``/``DeflateAlgorithm`` compression and decompression: driven by zlib directly instead of `NIOHTTPCompression`, producing the same wire format.
- ``RequestDL/BrotliURLSessionOnlyAlgorithm`` response decoding: it already only works under `.urlSession`, so a `NIOTransport`-off build loses nothing here.

## What changes

- ``Session/Executor/nioTransportServices``/`.nio` no longer exist as cases: ``Session/Executor`` only has `.urlSession` to offer, so ``Session/preferredExecutor(_:)``/``Session/requiredExecutor(_:)`` can't be called with anything else. This is enforced at compile time, not by a runtime error.
- `SecureConnection`'s modifiers that only take effect on a NIO-based executor are not declared: `keyLogger(_:)`, `shutdownTimeout(_:)`, `renegotiationSupport(_:)`, the signature-algorithm modifiers, `applicationProtocols(_:)`, `sendCANameListDisabled(_:)` and `cipherSuites(_:)`, and so is `SSLKeyLogger`, because `.urlSession` has no equivalent for them.
- `SecureConnection`'s TLS version range is still declared: `version(minimum:)`, `version(maximum:)`, `version(minimum:maximum:)` and the `Range`/`ClosedRange` variants. `.urlSession` applies both ends through `tlsMinimumSupportedProtocolVersion` and `tlsMaximumSupportedProtocolVersion`. App Transport Security still has the last word on the floor, see <doc:Configuring-App-Transport-Security-for-URLSession>.
- ``DataCache``'s on-disk storage goes through `FileManager`/`FileHandle` instead of `NIOFileSystem`, with the same public behavior.

## Topics

### Choosing an executor

- ``Session/preferredExecutor(_:)``
- ``Session/requiredExecutor(_:)``
