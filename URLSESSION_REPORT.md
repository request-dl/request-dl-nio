# URLSession Executor — Compatibility Report

**Status:** Analysis, plus one concrete bugfix landed along the way (§5.6), plus experimental validation of the highest-risk open item (mTLS from raw bytes, §5.1 — [request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287), closed as resolved). No URLSession executor code has been written yet.
**Scope:** Feasibility and compatibility mapping for adding URLSession as an alternate, automatically-selected executor alongside the existing AsyncHTTPClient/SwiftNIO backend, unified with the existing NIOTransportServices selection into one `Executor` model (§6).
**Non-goal of this document:** finalizing the public modifier names/placement on `Session`, the `IncompatibleExecutorConfigurationError` shape, or writing the actual URLSession-backed `Internals.Client`. Those are implementation-phase decisions that build on the findings and recommendations here.

---

## 1. Goal

Today, `RequestDL` decides between two transports under the hood:

- **NIOPosix + NIOSSL** — plain sockets, TLS implemented in Swift (SwiftNIO SSL / BoringSSL).
- **NIOTransportServices (Network.framework)** — used only when [`Internals.SecureConnection.isCompatibleWithNetworkFramework`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.SecureConnection.swift#L20-L38) is `true`, gated by the public [`Session.enableNetworkFramework(_:)`](Sources/RequestDL/Properties/Sources/Session/Session/Session.swift#L111-L113). Under the hood, this transport does **not** use NIOSSL at all — AsyncHTTPClient converts the built `NIOSSL.TLSConfiguration` into native `sec_protocol_options` (see §5.6) — so it's already using Apple's own TLS stack, the same one URLSession would use.

The goal is to add a **third transport, URLSession**, selected the same way — invisibly, based on whether the caller's configuration is representable on it — with automatic fallback to the existing NIO backend whenever it isn't. This report is step one: mapping exactly which configuration knobs can move to URLSession as-is, which need a different implementation, which need an OS-version gate, and which can never move.

---

## 2. Current architecture (for reference)

- Transport entry point: [`Internals.Client`](Sources/RequestDLInternals/Sources/Client/Client/Internals.Client.swift) wraps `AsyncHTTPClient.HTTPClient`.
- Pooling/reuse: [`Internals.ClientManager`](Sources/RequestDLInternals/Sources/Client/Client%20Manager/Internals.ClientManager.swift) caches clients keyed by provider + `SessionProviderOptions.isCompatibleWithNetworkFramework`.
- Event loop selection: [`Internals.IdentifiedSessionProvider`](Sources/RequestDLInternals/Sources/Session/Session%20Provider/Models/IdentifiedSessionProvider.swift) / [`SharedSessionProvider`](Sources/RequestDLInternals/Sources/Session/Session%20Provider/Models/SharedSessionProvider.swift) pick `NIOTSEventLoopGroup` vs `MultiThreadedEventLoopGroup` based on the same flag.
- TLS configuration: [`Internals.SecureConnection`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.SecureConnection.swift) builds an `NIOSSL.TLSConfiguration`.
- Request body streaming: [`RequestBody`](Sources/RequestDL/Request/RequestBody.swift) drives an `AsyncHTTPClient.HTTPClient.Body.StreamWriter` chunk-by-chunk via [`Internals.StreamWriterSequence`](Sources/RequestDLInternals/Sources/Body/Internals.StreamWriterSequence.swift), awaiting each write's `EventLoopFuture<Void>` before pulling the next chunk (explicit backpressure).
- Concurrency cap: [`Internals.Client.connectionSemaphore`](Sources/RequestDLInternals/Sources/Client/Client/Internals.Client.swift#L54) gates `execute()` before dispatch — see §5.2.

This is the pattern `isCompatibleWithURLSession` (§6) is modeled on.

---

## 3. iOS 26 research: dynamic certificates

Explicitly checked, since it changes the mTLS feasibility conclusion below.

- **No public API to build a `SecIdentity` from raw certificate + private key bytes on iOS**, confirmed via Apple Developer Forums threads and `Security/keychain/SecIdentity.h`. `SecIdentityCreateWithCertificate` (pairs a `SecCertificate` with a keychain-resident key) is **macOS-only**.
- The only public iOS paths are (a) `SecPKCS12Import` on an in-memory `.p12` blob, or (b) writing the private key into the Keychain and looking up the paired identity via `SecItemCopyMatching` (`kSecClass = kSecClassIdentity`).
- **No evidence of a new iOS 26 API closing this gap.** iOS 26 release notes highlight TLS 1.3 as the client default and post-quantum hybrid key exchange (HPKE) in URLSession/Network.framework by default — this narrows configurability further (e.g. reinforces that cipher-suite selection will not become public), it does not add raw-bytes identity construction.
- Server-side trust (custom CA / pinning from raw bytes) **is** solvable today via `SecTrust` + `SecTrustSetAnchorCertificates`, no version dependency.

This is why client certificates were tracked separately: [request-dl/request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287) ("Dynamic mTLS (cert/key from raw bytes) for the URLSession executor", category *Evolution*). **Update:** the Keychain round-trip path was subsequently built and validated end to end (§5.1) — this moved from bucket D to bucket C (§4.3), and the discussion is closed as resolved.

Sources consulted:
- [How to generate SecIdentityRef with SecCertificateRef and SecKeyRef on iOS](https://developer.apple.com/forums/thread/748892)
- [How can I create a SecIdentity instance on iOS](https://developer.apple.com/forums/thread/762996)
- [iOS & iPadOS 26 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes)
- [iOS 26 Security & Privacy Features Explained — NowSecure](https://www.nowsecure.com/blog/2025/09/19/ios-26-security-privacy-features-explained-essential-insights-for-developers-and-users/)

---

## 4. Compatibility mapping

Bucket definitions:

- **A — Drop-in.** Same public API, same behavior, no version gate.
- **B — Version-gated.** Same API/behavior, needs an `#available` check at runtime.
- **C — Reimplemented, API preserved.** The public `Session.foo()` modifier keeps working, but the underlying mechanism differs enough that edge cases, timing, or precision can diverge. Needs its own tests per executor.
- **D — Fallback-only.** No public URLSession/Network.framework equivalent. Presence of this config forces the NIO/Network executor, unconditionally.

Package platform floor: **iOS 15 / tvOS 15 / watchOS 8 / macOS 12** ([Package.swift:9-12](Package.swift#L9-L12)). Nearly every relevant URLSession API used below (`waitsForConnectivity` iOS 11+, `tlsMinimumSupportedProtocolVersion` iOS 13+, async/await task APIs iOS 15+) already sits at or below this floor — **bucket B is effectively empty today.** It's still worth building the version-gate mechanism for whatever Apple ships next, but it is not the blocker for a first delivery.

### 4.1 Bucket A — Drop-in

| Config | URLSession equivalent |
|---|---|
| [`networkFrameworkWaitForConnectivity`](Sources/RequestDL/Properties/Sources/Session/Session/Session.swift#L98-L100) | `URLSessionConfiguration.waitsForConnectivity` |
| `minimumTLSVersion` / `maximumTLSVersion` | `tlsMinimumSupportedProtocolVersion` / `tlsMaximumSupportedProtocolVersion` (iOS 13+, below floor) |
| `DataCache` / cache policy/strategy ([Internals.CacheConfiguration.swift](Sources/RequestDL/Properties/Sources/Cache/Cache%20Configuration/Internals.CacheConfiguration.swift)) | Fully custom cache (disk/memory), not `URLCache`-based — executor-agnostic. Only requirement: set `URLSessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData` (or `urlCache = nil`) so URLSession's own cache doesn't shadow it. |
| [`ReadingMode`](Sources/RequestDL/Properties/Sources/Headers/Reading%20Mode/ReadingMode.swift) (`.length`/`.separator`) | Re-chunking layer built on top of whatever raw byte stream the executor produces — works identically over `Data` chunks from URLSession. |
| `compression(_:)` (outgoing body gzip/deflate) | Currently wired through a NIO channel handler only for convenience; logically it's "compress `Data`, set `Content-Encoding`, send" — movable above the transport abstraction, reusable by both executors. |
| `httpVersion = .automatic` | URLSession's default negotiation behavior (ALPN-driven HTTP/1.1/2/3). |

### 4.2 Bucket B — Version-gated

Empty in practice given the current platform floor (§4, intro). Infrastructure for this should still exist in `isCompatibleWithURLSession` (§6) for future OS-gated features.

### 4.3 Bucket C — Reimplemented, API preserved

| Config | URLSession path | What changes |
|---|---|---|
| `redirectConfiguration` (`.disallow` / `.follow(max, allowCycles)`) | `URLSessionTaskDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` | No native "max redirects" / "allow cycles" — must be tracked and enforced manually per task. |
| `timeout.read` | `URLSessionConfiguration.timeoutIntervalForRequest` / `timeoutIntervalForResource` | Approximation, not a 1:1 semantic match. |
| `timeout.connect` | Approximated via `timeoutIntervalForRequest` (its clock starts before the connection is established, so a slow connect still trips it) | **Not isolated** from response time the way NIO's separate connect/read timeouts are. A fast-connect/slow-response case and a slow-connect/fast-response case become indistinguishable. **Decision:** keep as C (best-effort), not D — this is a precision loss, not a correctness violation. Must be documented on the public modifier and covered by a dedicated test that pins down the degraded behavior under URLSession. |
| `connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit` | `URLSessionConfiguration.httpMaximumConnectionsPerHost` | AsyncHTTPClient's soft limit vs. Apple's own heuristic; not honored under HTTP/2 multiplexing. |
| `proxy` (host/port + `.basic`/`.bearer`) | `connectionProxyDictionary` (legacy CFNetwork keys) + `URLSession:task:didReceive:` for the proxy auth challenge | Different configuration shape (untyped CF dictionary vs. typed struct), but host/port/basic auth are reachable. |
| `trustRoots` / `additionalTrustRoots` (bytes/file/certs) | `SecTrust` + `SecTrustSetAnchorCertificates` in the `NSURLAuthenticationMethodServerTrust` challenge | Moves from a static `TLSConfiguration` to a per-request/per-host delegate callback. |
| `certificateVerification` (`.none`, `.fullVerification`, `.noHostnameVerification`) | `.none` = accept any trust in the challenge; `.noHostnameVerification` = `SecPolicyCreateSSL(server: true, hostname: nil)` | Reachable via `SecPolicy` tricks; needs case-by-case validation. |
| Upload streaming ([`RequestBody`](Sources/RequestDL/Request/RequestBody.swift) / [`Internals.StreamWriterSequence`](Sources/RequestDLInternals/Sources/Body/Internals.StreamWriterSequence.swift)) | `uploadTask(withStreamedRequest:)` + `needNewBodyStream` returning an `InputStream` | Pull-based (the system asks for bytes) instead of the current push model with an `EventLoopFuture` awaited per chunk. Needs a bridging adapter (bounded buffer), not a reuse of the existing sequence. |
| Download streaming / `DownloadProgress` | `URLSessionDataDelegate.didReceive` + `didUpdateProgress` / `countOfBytesReceived` | Public API (`DownloadProgress.download(_:totalSize:)`) unchanged, but chunk size/timing is OS-determined, not caller-controlled. Any test asserting exact chunk boundaries breaks. |
| `certificateChain` + `privateKey` (mTLS from raw bytes/PEM/DER) — **moved from bucket D, §5.1** | Keychain round-trip: `SecItemAdd` the key and certificate, then `SecItemCopyMatching(kSecClassIdentity)` matched back by certificate bytes, then `URLCredential(identity:certificates:persistence:)` on the `NSURLAuthenticationMethodClientCertificate` challenge | Validated end to end on iOS Simulator and a physical device. Requires the app to carry a `keychain-access-groups` entitlement (Keychain Sharing capability) — see [HOW_TO_USE_CERTIFICATE_URLSESSION.md](HOW_TO_USE_CERTIFICATE_URLSESSION.md). RSA/PKCS#1 keys only so far; EC and PKCS#8 need their own DER framing. Not yet validated on tvOS/watchOS (expected to match) or non-sandboxed macOS (a different, unresolved issue — see §5.1). |

**Required normalizations (not features — side effects URLSession introduces on its own):**

- **Cookies.** URLSession persists cookies in `HTTPCookieStorage.shared` by default; the NIO backend has no cookie jar at all today. **Decision:** disable it explicitly on the URLSession configuration (`httpShouldSetCookies = false`, no shared `httpCookieStorage`) so switching executors never silently changes behavior. Revisit once RequestDL ships its own Cookies feature — at that point, decide whether it wraps `HTTPCookieStorage` or is fully independent of both executors.

### 4.4 Bucket D — Fallback-only

| Config | Why not |
|---|---|
| `renegotiationSupport` | No public equivalent. Canonical trigger example for forcing NIO/Network. |
| `signingSignatureAlgorithms` / `verifySignatureAlgorithms` | No public control over TLS signature algorithms. |
| `sendCANameList` | TLS protocol detail, not exposed. |
| `shutdownTimeout` | NIOSSL-specific; no analog in URLSession's pooled connection model. |
| `pskHint` / `pskIdentityResolver` (TLS-PSK) | Not exposed via `NWConnection`, let alone URLSession. |
| `cipherSuites` / `cipherSuiteValues` | No public cipher-suite selection API. iOS 26's TLS 1.3 + PQC-by-default direction narrows this further, not less. |
| `keyLogger` (`SSLKeyLogger`) | No public session-key export API. |
| `dnsOverride` | No public per-hostname DNS override for a URLSession session. |
| `httpVersion = .http1Only` | No stable public toggle to force HTTP/1.1-only. |
| `proxy.connectHeaders` (custom headers on `CONNECT`) | `connectionProxyDictionary` has no slot for this. |
| `proxy` with `.socks` + auth | SOCKS via `connectionProxyDictionary` is undocumented/unreliable enough not to treat as supported. |
| `decompression == .disabled` (explicit, non-Apple platforms) | Only reachable on Linux/Windows/Android now — see §5.4/5.5, resolved. |
| `maximumConcurrentConnections` | Not truly D — see §5.2. No native URLSessionConfiguration cap exists, but the gate is already implemented above the transport call in a way that can be shared. |

---

## 5. Resolved design decisions

### 5.1 mTLS from raw bytes (Keychain / PKCS#12) — resolved

**Status: validated.** Tracked at [request-dl/request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287), closed as resolved. Originally deferred to its own exploration (see §4.3's note on the same row) because the Keychain round-trip introduces real I/O/persistence/entitlement concerns NIOSSL's fully in-memory handling doesn't have — that concern was real, but turned out to be closeable, not a dead end.

**What was built and tested**, as two standalone spikes (not yet merged into RequestDL itself):

- `RawBytesIdentityBuilder`: PEM certificate + private key bytes → DER → `SecCertificate`/`SecKeyCreateWithData` → `SecItemAdd` for both into the Keychain → `SecItemCopyMatching(kSecClassIdentity)`, matched back to the right pair by comparing certificate bytes (identity queries don't reliably honor a label filter) → `SecIdentity`.
- `MTLSURLSessionDelegate`: presents that identity on the `NSURLAuthenticationMethodClientCertificate` challenge, via a real `URLSession`.

**What blocked early attempts, and why it isn't a real blocker:** every attempt that wasn't built through Xcode's actual signing pipeline — an unsigned `swift test` CLI binary on macOS, a hand-assembled `.app` bundle signed with a bare `codesign -s -` — hit `OSStatus -34018` (`errSecMissingEntitlement`) on the Keychain write. Manually stapling a `keychain-access-groups` entitlement on afterward didn't fix it either: SpringBoard refused to even launch an app whose entitlements weren't sealed in by a trusted signing identity. Once the identical code was built through a real `.xcodeproj` (generated via `tuist generate` — hand-writing a `.pbxproj` was judged too error-prone for a one-off spike) with the Keychain Sharing capability enabled, it worked immediately: no code changes, just the standard "Sign to Run Locally" identity for Simulator or a real Team + provisioning profile for device.

**Confirmed:**
- iOS Simulator, Xcode-signed build: identity synthesis **PASS**.
- A physical iOS device, signed under a corporate/enterprise Apple Developer team: identity synthesis **PASS**.
- A real HTTPS round-trip through `URLSession` using the built identity, against `https://client.badssl.com/` (which requires *a* client certificate, just not specifically ours): completed the TLS handshake and returned an HTTP-level 400 rather than a handshake failure — meaning the challenge fired, the identity was presented, negotiation completed, and the server's *application logic* rejected the specific certificate. That's the expected outcome for presenting the wrong (but well-formed, correctly-presented) client certificate, and confirms the full path works, not just the Keychain step in isolation.

**Not yet validated, tracked as follow-up rather than blockers:**
- tvOS/watchOS — expected to behave identically (same single data-protection-keychain model as iOS), not physically tested.
- macOS, sandboxed (Mac App Store) apps — expected to need the same Keychain Sharing capability, not tested.
- macOS, **non-sandboxed** apps — genuinely unresolved. An earlier CLI-only attempt (forcing the legacy, non-data-protection keychain to sidestep the entitlement issue) got past `SecItemAdd` for both the certificate and the key, confirmed both present via `security find-key`/`find-certificate`, but `SecItemCopyMatching(kSecClassIdentity)` never paired them — a different, still-open failure mode, unrelated to entitlements. Don't assume this works on non-sandboxed macOS without testing it directly.
- PKCS#8-wrapped keys and EC keys — the spike only handles RSA/PKCS#1 (`BEGIN RSA PRIVATE KEY`), matching the fixture it was validated against. Real support needs both, since PKCS#8 (`BEGIN PRIVATE KEY`) is the more common format modern tooling produces.

**Consumer-facing requirement, once this ships:** no RequestDL API changes — `SecureConnection { Certificates { ... }; PrivateKey(...) }` keeps working exactly as documented today. The one new thing an app developer needs to do is enable the **Keychain Sharing** capability in Xcode's Signing & Capabilities for any target that runs this code (including app extensions, which need their own). Full walkthrough, including troubleshooting the `-34018` failure mode: [HOW_TO_USE_CERTIFICATE_URLSESSION.md](HOW_TO_USE_CERTIFICATE_URLSESSION.md).

**Design implication:** unlike every other bucket-D/C determination in this report, whether Keychain Sharing is actually enabled is *not* something `Internals.SecureConnection` can know statically from the session's configuration — it's a fact about how the app was built, only observable at runtime (as a `SecItemAdd` failure). This means `certificateChain`/`privateKey` can be treated as URLSession-*compatible* in the static `isCompatibleWithURLSession` check (§6.2) — the configuration itself is fine — but the actual identity-build step still needs its own runtime error path distinct from the static `ExecutorIncompatibilityReason` system in §6.5, surfaced clearly enough that "I forgot to enable Keychain Sharing" is diagnosable from the error alone rather than presenting as a generic connection failure.

### 5.2 `maximumConcurrentConnections`

Already implemented correctly in terms of *where* it gates: [`Internals.Client.connectionSemaphore`](Sources/RequestDLInternals/Sources/Client/Client/Internals.Client.swift#L54) is awaited before the operation is registered and before `_client.execute(...)` is called ([Internals.Client.swift:109-130](Sources/RequestDLInternals/Sources/Client/Client/Internals.Client.swift#L109-L130)) — i.e., before the transport is touched at all.

What's missing for a second executor: the semaphore currently lives *inside* `Internals.Client`, which is the AsyncHTTPClient-specific wrapper. A future `Internals.URLSessionClient` would not inherit this for free — it would need to duplicate the semaphore logic, risking divergent cap behavior between executors. **Recommendation:** hoist this into a shared decorator (e.g. `Internals.ThrottledExecutor` wrapping either concrete client) so both executors share one code path for the cap, rather than each owning its own copy.

### 5.3 Cookies

Disable on the URLSession configuration (`httpShouldSetCookies = false`, no shared cookie storage) to match the NIO backend's current no-jar behavior exactly. Cookie support is planned as its own RequestDL feature later; that's where the decision of "use `HTTPCookieStorage` vs. a RequestDL-native jar, shared across executors or not" belongs — out of scope here.

### 5.4 `disableDecompression()` vs. `timeout.connect` — D-forced vs. best-effort

- **`disableDecompression()` → forced to bucket D.** There is no way to honor "give me the raw compressed bytes" via URLSession's public API. Silently serving decoded bytes when raw bytes were expected is a correctness violation (breaks manual decoders, checksums, or exact wire-size assumptions), not a degradable approximation. Any session that explicitly calls `.disableDecompression()` must resolve to NIO/Network. See §5.5 for how this interacts with the *default* state, which is no longer part of this fallback trigger on Apple platforms.
- **`timeout.connect` → stays in bucket C (best-effort).** The approximation via `timeoutIntervalForRequest` is coarser (doesn't isolate connect time from response time) but never produces a *wrong* result — worst case, a timeout fires for a different reason than the caller modeled. This must be documented on the public API and covered by an executor-specific test, but does not need to force a fallback.

### 5.5 `decompression` default — implemented

**Status: done.** [Internals.Session.Configuration.swift:16-27](Sources/RequestDLInternals/Sources/Session/Session%20Configuration/Internals.Session.Configuration.swift#L16-L27):

```swift
#if canImport(Darwin)
package var decompression: Internals.Decompression = .enabled(.none)
#else
package var decompression: Internals.Decompression = .disabled
#endif
```

Rationale for the split, not a flat flip:

- On Apple platforms, URLSession is a real future executor for a given session, and URLSession **always** auto-decompresses `Content-Encoding: gzip/deflate/br` with **no way to opt out and no size/ratio limit**. Defaulting the NIO backend to match (`.enabled(.none)`) removes the single biggest reason (§4.4, prior revision of this document) most existing sessions would have been executor-incompatible by default, and — more importantly — keeps behavior identical regardless of which executor a given request actually lands on.
- On non-Apple platforms (Linux/Windows/Android), URLSession/Network.framework is never a candidate executor, so there is nothing to keep parity with; `.disabled` is kept there as the conservative default.

**Security trade-off, accepted deliberately:** `.enabled(.none)` has no decompression-bomb guard — a small compressed payload can expand to consume large amounts of memory. This mirrors URLSession's own lack of a limit on Apple platforms exactly (not a regression relative to what URLSession-based code already lives with), but it *is* a new default risk for the NIO backend on Apple platforms specifically, where before this change no decompression happened at all by default. Callers with unusual size/ratio safety requirements on Apple platforms should call `.decompressionLimit(_:)` explicitly.

`.disableDecompression()` continues to force the NIO/Network executor (§5.4) — it remains the only way to get untouched wire bytes back, on any platform, now that it's meaningfully different from the default rather than redundant with it.

Tests updated: [InternalsSessionConfigurationTests.swift:247-283](Tests/RequestDLInternalsTests/Sources/Session/Session%20Configuration/InternalsSessionConfigurationTests.swift#L247-L283) (`configuration_whenInit_shouldBeDefault`) now asserts the platform-conditional default explicitly.

### 5.6 `isCompatibleWithNetworkFramework` was incomplete — fixed

**Status: done.** Found while designing the unified executor model (§6): AsyncHTTPClient's own NIOTransportServices bridge — [`TLSConfiguration.getNWProtocolTLSOptions`](https://github.com/swift-server/async-http-client/blob/main/Sources/AsyncHTTPClient/NIOTransportServices/TLSConfiguration.swift), which converts the built `NIOSSL.TLSConfiguration` into native `sec_protocol_options` when running on Network.framework — handles far more `SecureConnection` fields than the old check accounted for, and not always safely:

- **Traps via `precondition` (process crash) on:** `certificateChain`, `privateKey`, `keyLogger` (all three were already excluded) — plus **`certificateVerification == .noHostnameVerification`**, which was **not** excluded. Any session with `.noHostnameVerification` set and `enableNetworkFramework(true)` on would crash the process, reachable through public API.
- **Silently ignored (no crash, no application, no signal) on:** `cipherSuiteValues`, `additionalTrustRoots`, `renegotiationSupport`, `signingSignatureAlgorithms`, `verifySignatureAlgorithms`, `sendCANameList`, `shutdownTimeout`, `pskHint`, `pskIdentityResolver` — **none** of these were excluded either. Most concerning: `additionalTrustRoots` — a session trusting an extra CA and also on Network Framework would silently connect *without* that extra trust anchor, changing which servers it accepts with no error.

Fixed at [Internals.SecureConnection.swift:20-38](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.SecureConnection.swift#L20-L38) — `isCompatibleWithNetworkFramework` now excludes all of the above, falling back to plain NIOPosix + NIOSSL for any of them instead of crashing or silently dropping the setting. Regression coverage: [InternalsSecureConnectionTests.swift](Tests/RequestDLInternalsTests/Sources/Secure%20Connection/Secure%20Connection/InternalsSecureConnectionTests.swift) — one parameterized test per newly-excluded field, plus the crash-triggering `.noHostnameVerification` case specifically.

This was a pre-existing bug independent of the URLSession work — found only because unifying the two compatibility checks (§6) required reading AsyncHTTPClient's actual NIOTS behavior line by line instead of trusting the existing 4-field check.

---

## 6. Executor resolution model

### 6.1 Not a strict hierarchy

A natural first instinct is "URLSession-compatible implies NIOTransportServices-compatible" (both are Apple's native TLS stack, so a config too advanced for one should be too advanced for the other too) — **this is false**. Concrete counter-example: `additionalTrustRoots`.

- Under **NIOTransportServices**, it's silently dropped (§5.6) — today, fixed to correctly report incompatibility, forcing fallback to plain NIO.
- Under **URLSession**, it's fully reachable (bucket C, §4.3) via `SecTrust` + `SecTrustSetAnchorCertificates` in the server-trust challenge — a delegate callback has no equivalent of AsyncHTTPClient's static `sec_protocol_options` conversion to worry about.

So for this one field, URLSession is *more* capable than NIOTransportServices, not less. The reverse is also true elsewhere — `dnsOverride`, `proxy.connectHeaders`, `httpVersion = .http1Only`, and an un-opted-in `decompression == .disabled` (non-Apple platforms only, post-§5.5) all work fine under NIOTransportServices (they're AsyncHTTPClient/HTTP-layer concerns, orthogonal to which socket/TLS transport is underneath) but are bucket D for URLSession. **The three executors need three independent capability checks, evaluated in priority order — not one check gating a nested set of the others.**

### 6.2 Proposed `Executor` enum

```swift
package enum Executor: Sendable, Hashable {
    case urlSession
    case nioTransportServices
    case nio
}
```

`Internals.SecureConnection.isCompatibleWithNetworkFramework` (→ `.nioTransportServices`) is implemented today (§5.6, corrected). `isCompatibleWithURLSession` (→ `.urlSession`) is still only a sketch:

```swift
extension Internals.SecureConnection {

    /// `true` when nothing here requires NIOSSL-level control that URLSession has no public
    /// equivalent for. Deliberately more permissive than `isCompatibleWithNetworkFramework` on
    /// `additionalTrustRoots` and `certificateVerification` — see §6.1.
    package var isCompatibleWithURLSession: Bool {
        signingSignatureAlgorithms == nil
            && verifySignatureAlgorithms == nil
            && sendCANameList == nil
            && renegotiationSupport == nil
            && shutdownTimeout == nil
            && pskHint == nil
            && pskIdentityResolver == nil
            && keyLogger == nil
            && cipherSuites == nil
            && cipherSuiteValues == nil
        // trustRoots / additionalTrustRoots / certificateVerification (incl. .noHostnameVerification):
        // bucket C, reachable via SecTrust/SecPolicy — NOT excluded here, unlike NIOTS.
        //
        // certificateChain / privateKey: bucket C as of §5.1 (validated) — reachable via a
        // Keychain round-trip. NOT excluded here. Whether the app actually has the Keychain
        // Sharing entitlement it needs is a runtime fact this static check cannot see; see §5.1's
        // "Design implication" and §6.5.
    }
}

extension Internals.Session.Configuration {

    package var isCompatibleWithURLSession: Bool {
        guard secureConnection?.isCompatibleWithURLSession ?? true else { return false }
        guard dnsOverride.isEmpty else { return false }                                // bucket D
        guard httpVersion != .http1Only else { return false }                          // bucket D
        guard proxy?.connectHeaders.isEmpty ?? true,
              proxy?.connectionProtocol != .socks else { return false }                // bucket D
        guard case .enabled = decompression else { return false }                      // bucket D — see note
        return true
    }
}
```

Note on the `decompression` guard: post-§5.5, the *default* is already `.enabled(.none)` on Apple platforms, so this guard now only rejects an explicit `.disableDecompression()` call — it stopped being the "rejects almost everyone by default" trap described in the original revision of this section.

### 6.3 Resolution order

```swift
extension Internals.Session.Configuration {

    package func resolveExecutor() -> Executor {
        #if canImport(Darwin)
        if isCompatibleWithURLSession {
            return .urlSession
        }
        if secureConnection?.isCompatibleWithNetworkFramework ?? true {
            return .nioTransportServices
        }
        #endif
        return .nio
    }
}
```

URLSession is tried first on Apple platforms — best OS integration (background transfers, ATS, HTTP/3 maturity are all URLSession-only capabilities NIO/NIOTS can't match) — then NIOTransportServices, then plain NIO as the universal fallback. This ordering is a default, not a fixed law — see §6.4.

### 6.4 `preferredExecutor` vs. `requiredExecutor` — two different commitment levels, not two names for the same thing

Raised as an open question: should the caller be able to influence which `Executor` gets picked? Recommendation is to ship **two** modifiers sharing the `Executor` vocabulary above, because they mean genuinely different things:

- **`preferredExecutor(_:)` — soft hint, always safe.** A tiebreaker among executors the config already supports, not an override of §6.3's compatibility checks. If the caller asks for `.urlSession` but the config sets `pskIdentityResolver`, resolution still lands on `.nio` — the preference only reorders the *compatible* candidates, it never forces an incompatible one. This is the default, invisible mechanism the whole exercise (§1) was for, and it's always correctness-preserving by construction.
- **`requiredExecutor(_:)` — hard pin, must fail loudly, not silently.** For debugging, benchmarking, or a caller who knows their deployment target and wants a guaranteed transport. The behavior that must be rejected here is "ignore whatever the pinned executor can't do" — that's exactly the failure mode §5.6 just found and fixed as a bug (NIOTransportServices silently dropping `additionalTrustRoots`). Institutionalizing "silently ignore incompatible settings" as `requiredExecutor`'s contract would reintroduce the same bug class on purpose, just moved to a different call site. Instead, `requiredExecutor(.nioTransportServices)` on a config with `additionalTrustRoots` set should throw a typed, descriptive error (e.g. `IncompatibleExecutorConfigurationError` naming the conflicting fields) at session-build time — giving the caller full control without ever trading away correctness silently.

Both modifiers should resolve through the same underlying capability data (§6.5) — `preferredExecutor` uses it to pick among compatible options, `requiredExecutor` uses it to decide whether to throw.

### 6.5 `IncompatibleExecutorConfigurationError` shape

Follows the existing house pattern for this exact kind of split — compare [`Internals.SecureFileLoadError`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Models/Internals.SecureFileLoadError.swift) (raw, package-visible, minimal) rewrapped into [`SecureFileError`](Sources/RequestDL/Properties/Sources/Secure%20Connection/Secure%20Connection/Models/SecureFileError.swift) (public, descriptive, actionable) at the point `RequestDL` catches it — [RawTask.swift:31-32](Sources/RequestDL/Tasks/Sources/Raw%20Task/Raw/RawTask.swift#L31-L32). The natural catch site for this new error is the same one.

**Prerequisite refactor:** §6.2's two capability checks currently return `Bool`. To back a typed error *and* stay the single source of truth for `preferredExecutor`'s fallback logic, they need to return the specific reasons instead, with the `Bool` becoming `reasons.isEmpty`:

```swift
extension Internals {

    /// One entry per configuration field that keeps a session off a given executor. Named per
    /// bucket-D/§5.6 finding, not per executor, since the same field can be fine on one executor
    /// and not another (§6.1) — the two `*IncompatibilityReasons()` functions below decide which
    /// reasons apply for which executor.
    package enum ExecutorIncompatibilityReason: Sendable, Hashable {
        case certificateChain
        case privateKey
        case keyLogger
        case cipherSuites
        case cipherSuiteValues
        case renegotiationSupport
        case signingSignatureAlgorithms
        case verifySignatureAlgorithms
        case sendCANameList
        case shutdownTimeout
        case pskHint
        case pskIdentityResolver
        case noHostnameVerificationUnderNetworkFramework  // NIOTS-only, §5.6 — fine under URLSession
        case additionalTrustRootsUnderNetworkFramework     // NIOTS-only, §5.6 — fine under URLSession
        case dnsOverrideUnderURLSession
        case http1OnlyUnderURLSession
        case proxyConnectHeadersUnderURLSession
        case proxySOCKSUnderURLSession
        case decompressionDisabledUnderURLSession
    }

    package struct IncompatibleExecutorConfigurationError: Error, Sendable {
        package let requiredExecutor: Executor
        package let reasons: [ExecutorIncompatibilityReason]
    }
}

extension Internals.SecureConnection {

    package func networkFrameworkIncompatibilityReasons() -> [Internals.ExecutorIncompatibilityReason] {
        var reasons: [Internals.ExecutorIncompatibilityReason] = []
        if certificateChain != nil { reasons.append(.certificateChain) }
        if privateKey != nil { reasons.append(.privateKey) }
        if keyLogger != nil { reasons.append(.keyLogger) }
        if certificateVerification == .noHostnameVerification {
            reasons.append(.noHostnameVerificationUnderNetworkFramework)
        }
        if cipherSuites != nil { reasons.append(.cipherSuites) }
        if cipherSuiteValues != nil { reasons.append(.cipherSuiteValues) }
        if additionalTrustRoots != nil { reasons.append(.additionalTrustRootsUnderNetworkFramework) }
        if renegotiationSupport != nil { reasons.append(.renegotiationSupport) }
        if signingSignatureAlgorithms != nil { reasons.append(.signingSignatureAlgorithms) }
        if verifySignatureAlgorithms != nil { reasons.append(.verifySignatureAlgorithms) }
        if sendCANameList != nil { reasons.append(.sendCANameList) }
        if shutdownTimeout != nil { reasons.append(.shutdownTimeout) }
        if pskHint != nil { reasons.append(.pskHint) }
        if pskIdentityResolver != nil { reasons.append(.pskIdentityResolver) }
        return reasons
    }

    /// `isCompatibleWithNetworkFramework` (shipped, §5.6) becomes `networkFrameworkIncompatibilityReasons().isEmpty`
    /// once this lands — same result, single source of truth instead of two lists that can drift
    /// apart again the way the original 4-field check did.

    /// Deliberately does *not* check `certificateChain`/`privateKey` — §5.1 validated the
    /// Keychain round-trip that makes them reachable under URLSession. What it can't check is
    /// whether the app actually carries the Keychain Sharing entitlement that round-trip needs
    /// at runtime — that's a build-time fact about the app, invisible to a static config check.
    /// A missing entitlement surfaces at identity-build time as its own runtime error, not as a
    /// reason in this list — see the note below the function.
    package func urlSessionIncompatibilityReasons() -> [Internals.ExecutorIncompatibilityReason] {
        var reasons: [Internals.ExecutorIncompatibilityReason] = []
        if signingSignatureAlgorithms != nil { reasons.append(.signingSignatureAlgorithms) }
        if verifySignatureAlgorithms != nil { reasons.append(.verifySignatureAlgorithms) }
        if sendCANameList != nil { reasons.append(.sendCANameList) }
        if renegotiationSupport != nil { reasons.append(.renegotiationSupport) }
        if shutdownTimeout != nil { reasons.append(.shutdownTimeout) }
        if pskHint != nil { reasons.append(.pskHint) }
        if pskIdentityResolver != nil { reasons.append(.pskIdentityResolver) }
        if keyLogger != nil { reasons.append(.keyLogger) }
        if cipherSuites != nil { reasons.append(.cipherSuites) }
        if cipherSuiteValues != nil { reasons.append(.cipherSuiteValues) }
        return reasons
    }
}
```

The Keychain Sharing entitlement gap this leaves needs a second, runtime-only error path — a session can be statically `isCompatibleWithURLSession` and still fail to actually build a client identity because the app wasn't set up for it (§5.1's "Design implication"). That path should wrap the underlying `SecItemAdd`/`errSecMissingEntitlement` failure with the same actionable framing [HOW_TO_USE_CERTIFICATE_URLSESSION.md](HOW_TO_USE_CERTIFICATE_URLSESSION.md) already documents by hand, rather than letting a raw `OSStatus` reach the caller.

Resolution (§6.3) and the hard pin both read from the same data:

```swift
extension Internals.Session.Configuration {

    package func resolveExecutor() -> Executor {
        #if canImport(Darwin)
        if urlSessionIncompatibilityReasons().isEmpty {
            return .urlSession
        }
        if secureConnection?.networkFrameworkIncompatibilityReasons().isEmpty ?? true {
            return .nioTransportServices
        }
        #endif
        return .nio
    }

    package func requireExecutor(_ executor: Executor) throws {
        let reasons: [Internals.ExecutorIncompatibilityReason]
        switch executor {
        case .urlSession: reasons = urlSessionIncompatibilityReasons()
        case .nioTransportServices: reasons = secureConnection?.networkFrameworkIncompatibilityReasons() ?? []
        case .nio: reasons = []  // universal fallback — always compatible
        }

        guard reasons.isEmpty else {
            throw Internals.IncompatibleExecutorConfigurationError(
                requiredExecutor: executor,
                reasons: reasons
            )
        }
    }
}
```

Public rewrap, following `SecureFileError`'s style of naming the fix, not just the failure:

```swift
public struct ExecutorRequirementError: Error, Sendable {
    public let requiredExecutor: Session.Executor
    public let reasons: [Reason]  // public-facing mirror of Internals.ExecutorIncompatibilityReason

    init(_ error: Internals.IncompatibleExecutorConfigurationError) { /* ... */ }
}

extension ExecutorRequirementError: CustomStringConvertible {
    public var description: String {
        """
        RequestDL could not honor .requiredExecutor(.\(requiredExecutor)) because this session's \
        configuration uses: \(reasons.map(\.description).joined(separator: ", ")). Use \
        .preferredExecutor(_:) instead to let RequestDL fall back automatically, or remove the \
        conflicting configuration.
        """
    }
}
```

Still open for the next design pass (explicitly not decided here):

- Whether `isCompatibleWithURLSession`/`urlSessionIncompatibilityReasons()` also needs an `#available`-based component once bucket B (§4.2) stops being empty.
- Exact modifier names/placement on `Session`, and whether `enableNetworkFramework(_:)` gets deprecated in favor of `preferredExecutor(.nioTransportServices)`.
- Public naming for `Reason`'s cases (`ExecutorIncompatibilityReason` is package-internal; the public mirror should read well in an error message, e.g. `.noHostnameVerificationUnderNetworkFramework` → something more prose-like).
- Hoisting `connectionSemaphore` per §5.2 before or alongside the second executor landing.
- The upload/download bridging adapter design referenced in §4.3.
- The runtime-only error path for a missing Keychain Sharing entitlement (§5.1, §6.5) — shape, and whether it reuses `IncompatibleExecutorConfigurationError` or is its own type given it can't be known statically.
- PKCS#8/EC key support for the raw-bytes identity builder (§5.1) — RSA/PKCS#1 only so far.
- tvOS/watchOS and non-sandboxed macOS validation for the same (§5.1) — non-sandboxed macOS specifically hit a distinct, unresolved identity-pairing issue, not just an entitlement one.

---

## 7. References

- Discussion: [request-dl/request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287) — dynamic mTLS via Keychain round-trip, **closed as resolved**.
- [HOW_TO_USE_CERTIFICATE_URLSESSION.md](HOW_TO_USE_CERTIFICATE_URLSESSION.md) — the consumer-facing walkthrough (Keychain Sharing capability, troubleshooting `-34018`) resulting from §5.1.
- Spike source: `Tests/RequestDLTests/URLSession Executor Spike/` (`RawBytesIdentityBuilder.swift`, `MTLSURLSessionDelegate.swift`) — not part of the public API, throwaway validation code referenced throughout §5.1 and §6.
- [SecIdentity generation on iOS — Apple Developer Forums](https://developer.apple.com/forums/thread/748892)
- [iOS & iPadOS 26 Release Notes — Apple](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes)
- [iOS 26 Security & Privacy Features Explained — NowSecure](https://www.nowsecure.com/blog/2025/09/19/ios-26-security-privacy-features-explained-essential-insights-for-developers-and-users/)
- [AsyncHTTPClient — NIOTransportServices/TLSConfiguration.swift](https://github.com/swift-server/async-http-client/blob/main/Sources/AsyncHTTPClient/NIOTransportServices/TLSConfiguration.swift) — source of the §5.6 bug finding, checked out locally at `.build/checkouts/async-http-client`.
