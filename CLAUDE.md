# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

RequestDL is a Swift package providing a SwiftUI-style declarative API for HTTP networking, built on top of `async-http-client` / SwiftNIO. Requests are described with the `Property` protocol and `@PropertyBuilder`, resolved into a request/session configuration, and executed by `RequestTask` types (`DataTask`, `DownloadTask`, `UploadTask`).

Supported platforms: macOS 12+, iOS 15+, tvOS 15+, watchOS 8+, and Linux. Swift tools version 6.2.

## Commands

```bash
# Build
swift build

# Run all tests (uses swift-testing, not XCTest)
swift test

# Run a single test target/case/method
swift test --filter RequestDLTests.NeverPropertyTests
swift test --filter RequestDLTests.NeverPropertyTests/neverBody

# Lint / format (config in .swift-format at repo root)
swift format lint --recursive --strict Sources Tests
swift format format --in-place --recursive Sources Tests
```

All tests use the `Testing` framework (`import Testing`, `@Test`, `struct ...Tests`) — there is no XCTest anywhere in `Tests/RequestDLTests`.

CI (`.github/workflows/swift-ci.yaml`) runs formatting, an API-breaking-changes check, Apple + Linux ("third-party") test suites, and a Foundation-linkage check via a shared reusable workflow. Recent history on this branch is dominated by Linux/watchOS/Darwin build fixes and a test-timeout fix — cross-platform correctness is a live concern, not a hypothetical.

## Architecture

The codebase is organized into three top-level modules under `Sources/RequestDL/`, each split into `Sources/` (implementation) and `Extensions/` (protocol extensions/conveniences):

- **`Properties/`** — the public declarative API: `Property` protocol, `@PropertyBuilder`, and all concrete properties (`Headers`, `Payloads`, `Query`/`Value`, `Cache`, `Secure Connection`, `Session`, `URL`, etc). This is the largest module and what most call sites touch.
- **`Internals/`** — the execution engine wrapping AsyncHTTPClient/SwiftNIO (`Client`, `Session`, `Body`, `Buffers`, `Stream`, `Secure Connection`, `Cache`, `Storage`, `Logger`). Nothing here is public API; it's namespaced under the `Internals` enum.
- **`Tasks/`** — entry points (`DataTask`, `DownloadTask`, `UploadTask`) and the post-execution pipeline (`Modifiers`, `Interceptors`).

Plus `Sources/RequestDL/Request/` — just two files, `RequestConfiguration` (the fully-resolved, url/method/headers/body struct that gets converted straight into `HTTPClient.Request`) and `RequestBody`.

### Request pipeline (declarative tree → wire request)

1. **`Property` tree.** A `Property` has a `body` built via `@PropertyBuilder`; the builder produces composite wrapper types (`_PartialContent`, `_OptionalContent`, `_EitherContent`, in `Properties/Sources/Extra Properties/`). There's no separate tree-building pass — walking `_makeProperty(property:inputs:)` recursively down `body` *is* how the tree gets built and consumed at once.
2. **Graph (`Properties/Sources/Graph/`).** Each concrete property conforms to `PropertyNode`, whose `make(_ make: inout Make) async throws` mutates the in-progress request state. `LeafNode<Property: PropertyNode>` wraps a resolved property as a graph leaf; `_GraphValue` is the typed traversal reference.
3. **`Resolve` (`Properties/Sources/Graph/Resolve/Resolve.swift`).** The entry point: drives the `_makeProperty` walk to get a root `Node`, then walks that node tree calling `PropertyNode.make(&make)` for every node to populate `Make` (`sessionConfiguration: Internals.Session.Configuration`, `requestConfiguration: RequestConfiguration`, cache config, proxy). `Resolve.build()` returns a `Resolved` (session + request configuration + data cache) — the handoff object into `Internals`. System-proxy resolution deliberately happens here rather than in a node, since it needs the final URL after all properties (e.g. `BaseURL`) have contributed.
4. **`Internals.Session` / `Internals.Client`.** `Session.execute(requestConfiguration:dataCache:logger:)` gets a pooled `Internals.Client` from `Internals.ClientManager`, checks `CacheControl`/`dataCache`, builds an `HTTPClient.Request` (`RequestConfiguration.build(eventLoop:)`), and executes it. Streaming responses flow through `Internals.ClientResponseReceiver` → `Internals.AsyncResponse`, exposing upload progress, response head, and body bytes as async sequences.
5. **`RawTask<Content: Property>`** (`Tasks/Sources/Raw Task/`) is the common bridge: `result()` resolves the property tree and calls `session.execute(...)`, returning `Internals.AsyncResponse`. `DataTask`/`DownloadTask`/`UploadTask` each wrap a `RawTask` and post-process its response into their own result type.
6. **`RequestTask` pipeline.** All task types conform to `protocol RequestTask<Element>` (single requirement: `result() async throws -> Element`). `.modifier(_:)` wraps in `ModifiedRequestTask`, transforming `Element` via `RequestTaskModifier.body(_:) async throws -> Output` (e.g. `Modifiers.Decode`, `.Map`, `.ExtractPayload`). `.interceptor(_:)` wraps in `InterceptedRequestTask`, a side-effect-only observer via `RequestTaskInterceptor.output(_ result: Result<Element, Error>)` (e.g. `Interceptors.Breakpoint`, `.Detach`) that does not change `Element`.

### Secure Connection (TLS)

`Properties/Sources/Secure Connection/` (Certificate, Certificates, Trusts, Additional Trusts, Private Key, PSK, SPKI Pinning) are `Property`/`PropertyNode` types that populate `make.sessionConfiguration.secureConnection`. Their NIOSSL-facing counterparts live in `Internals/Sources/Secure Connection/`; `Internals.SecureConnection.build()` produces the `TLSConfiguration` consumed when building `HTTPClient.Configuration`.

### Testing conventions

- Use the `resolve(_:)` helper (`Tests/RequestDLTests/Utils/resolve.swift`) to run a `Property` through `Resolve(...).build()` and inspect the resulting `Resolved` in unit tests, rather than executing a real task.
- `TestProperty` (`Tests/RequestDLTests/Utils/TestProperty.swift`) wraps a property under a default `BaseURL("www.apple.com")` for tests that need a valid resolvable tree.
- Test files mirror the `Sources/` directory layout 1:1 under `Tests/RequestDLTests/`.

### Cross-platform notes

- Prefer `#if canImport(FoundationEssentials) / import FoundationEssentials #else / import Foundation #endif` (or importing only the specific Foundation types needed, e.g. `import struct Foundation.Date`) over a blanket `import Foundation`, matching existing usage — full Foundation isn't available/lightweight on all supported platforms.
- Several Internals/Secure Connection paths differ between Darwin and Linux (`canImport(Darwin)`/`canImport(Glibc)`, `os(Linux)`); when touching networking/TLS/session code, check for existing platform branches before assuming one code path.

### Style

- License header on every file: `// See LICENSE for this package's licensing information.` (see `.swift-format`/existing files for exact formatting).
- 4-space indentation, 120-char line length, enforced by `.swift-format` — run `swift format` rather than hand-wrapping lines.
