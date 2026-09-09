# Configuration-driven requests

Drive a request's properties — base URL, headers, authentication, proxy, secure connection, caching, and more — from an external configuration source instead of hardcoding them as Swift literals.

## Overview

``RequestDL/Configured`` reads from a swift-configuration `ConfigReader` — backed by environment variables, a JSON file, in-memory defaults, or any other `ConfigProvider` — and composes the same properties you'd otherwise write by hand (``RequestDL/BaseURL``, ``RequestDL/Authorization``, ``RequestDL/Proxy``, ``RequestDL/SecureConnection``, ...). Nothing about the resulting request is special-cased: a config-driven property and a literal one resolve exactly the same way, and the two compose freely in the same `@PropertyBuilder` block.

```swift
DataTask {
    Configured(appConfig)
}
```

> Important: `Configured` is gated to `macOS 15`, `iOS 18`, `watchOS 11`, `tvOS 18`, and `visionOS 2` — every symbol in swift-configuration's `Configuration` module carries that same availability. This is a per-symbol gate, not a change to the package's own platform floor: every other RequestDL property keeps working on its existing, older minimums.

`ConfigReader.scoped(to:)` lets multiple endpoints share one reader under different key prefixes, so a single configuration source can back several distinct `Configured` declarations:

```swift
DataTask {
    Configured(appConfig.scoped(to: "usersAPI"))
}
```

### A basic setup

The simplest case reads a host, an HTTP method, a timeout, and a handful of headers and query parameters:

```swift
let provider = InMemoryProvider(values: [
    "baseURL": "https://api.example.com",
    "method": "post",
    "timeout": 30,
    "headers": .init(.stringArray(["X-Api-Version: 2"]), isSecret: false),
    "queries": .init(.stringArray(["locale=en_US"]), isSecret: false),
])

DataTask {
    Configured(ConfigReader(provider: provider))
}
```

Every key is read independently and is entirely optional — a missing key contributes nothing, the same as any other absent property. `baseURL` is passed to ``RequestDL/FlexibleURL``, not ``RequestDL/BaseURL``, since it also accepts a relative path (`"/users/123"`, appended to whatever base URL is otherwise in effect) or a complete URL that overrides it outright — see ``RequestDL/Configured`` for the full key-by-key reference.

### Authentication and proxying

`authorization` and `proxy` are scoped keys: each reads a handful of related sub-keys together, rather than a single flat value.

```swift
let provider = InMemoryProvider(values: [
    "authorization.scheme": "bearer",
    "authorization.token": apiToken,

    "proxy.enabled": true,
    "proxy.host": "proxy.example.com",
    "proxy.port": 8080,
])

DataTask {
    BaseURL("api.example.com")
    Configured(ConfigReader(provider: provider))
}
```

Unlike the properties in the basic setup above, these two — along with `secureConnection.privateKey` and `redirect` — validate what they read: an unrecognized `authorization.scheme`, a `proxy.enabled` without a `proxy.host`, and similar genuinely-invalid combinations throw ``RequestDL/ConfiguredError`` rather than silently doing nothing.

### Secure connection

`secureConnection.trustRoots`, `.additionalTrustRoots`, and `.certificates` each take a path to a `PEM` file and delegate straight to ``RequestDL/TrustRoots``, ``RequestDL/AdditionalTrustRoots``, and ``RequestDL/Certificates`` — none of which require nesting inside a ``RequestDL/SecureConnection`` wrapper. `secureConnection.tlsMinimumVersion`/`.tlsMaximumVersion` are the exception: configuring `SecureConnection` itself, rather than a certificate, does need that wrapper.

```swift
let provider = InMemoryProvider(values: [
    "secureConnection.certificates": "/path/to/client.pem",
    "secureConnection.privateKey.file": "/path/to/key.pem",
    "secureConnection.tlsMinimumVersion": "1.2",
])

DataTask {
    BaseURL("api.example.com")
    Configured(ConfigReader(provider: provider))
}
```

### Overriding a config-driven value

An explicit property declared after `Configured` in the same `@PropertyBuilder` block still wins — the same "last one wins" precedent ``RequestDL/BaseURL`` and ``RequestDL/DNSOverride`` already establish for repeated declarations:

```swift
DataTask {
    Configured(appConfig)
    Timeout(.seconds(5))  // overrides whatever "timeout" the config specified
}
```

## Topics

### Reading configuration

- ``RequestDL/Configured``
- ``RequestDL/ConfiguredError``
