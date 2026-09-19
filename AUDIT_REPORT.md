# RequestDL Internals Audit Report

**Date:** 2026-09-19
**Scope:** `Sources/**/*.swift`, with emphasis on `Sources/RequestDLInternals/`
**Method:** Manual code audit across four lenses — integrity, performance, security, availability — with particular attention to divergence between the SwiftNIO-backed (`NIOTransport` trait, default) and portable (`--disable-default-traits`, URLSession/Network.framework-only) code paths.
**Status:** All 10 findings addressed. #1-#7, #9, #10 fixed and verified; #8 partially fixed (its quadratic-rescan half fixed, its unbounded-buffer half deliberately left open, see that finding's section). Build clean on both trait configurations; lint clean; targeted regression tests passing throughout.

---

## Summary

| # | Finding | Category | Verdict | Severity |
|---|---|---|---|---|
| 1 | Multipart `Content-Disposition` header injection | Security | **FIXED** | Critical |
| 2 | TLS pinning / trust roots dropped after cross-host redirect (`.urlSession`) | Security | **FIXED** | Critical |
| 3 | `revocationPolicy` / `trustDecisionObserver` silently dropped on NIOSSL path | Security | **FIXED** | High |
| 4 | Buffer/cache files created world-readable (0644) on NIO backend | Security | **FIXED** | High |
| 5 | `IdentityManager.release` may delete Keychain items of a newer handle | Security | **FIXED** (upgraded to CONFIRMED) | High |
| 6 | Unbounded PAC proxy cache + one OS thread per cache miss | Availability | **FIXED** | Medium |
| 7 | Cache directory scan stalls 15s per incomplete entry | Availability | **FIXED** | Medium |
| 8 | SSE parser has unbounded line buffer + quadratic rescan | Availability | **PARTIALLY FIXED** | Medium |
| 9 | HTTP disk cache never hits for responses without `Content-Length` | Integrity | **FIXED** | Medium |
| 10 | `ReadingMode(length: 0)` silently discards the entire response body | Integrity | **FIXED** | Low |

---

## 1. Multipart `Content-Disposition` header injection

**Category:** Security · **Verdict:** CONFIRMED · **Status: FIXED**

**Location:** [`FormItem.swift:118-126`](Sources/RequestDL/Properties/Sources/Payloads/Form%20Group/Models/FormItem.swift#L118-L126) (note: the original finding cited this file's path for `Form.swift` too — `Form.swift` actually lives at [`Sources/RequestDL/Properties/Sources/Payloads/Form/Form.swift`](Sources/RequestDL/Properties/Sources/Payloads/Form/Form.swift), a sibling directory, not under `Form Group/Models/`)

```swift
var contentDisposition = "form-data; name=\"\(name)\""
if let filename {
    contentDisposition += "; filename=\"\(filename)\""
}
```

Neither `"` nor CR/LF is escaped or rejected in `name`/`filename`. The result is written verbatim into the body bytes by `FormGroupBuilder.buildHeadersBuffer` ([`FormGroupBuilder.swift:88-97`](Sources/RequestDL/Properties/Sources/Payloads/Form%20Group/Models/FormGroupBuilder.swift#L88-L97)), so nothing downstream (NIOHTTP1, CFNetwork) validates it — these are body bytes, not transport headers. `Form(name:filename:contentType:url:)` defaults `filename` to `url.lastPathComponent` ([`Form.swift:117-132`](Sources/RequestDL/Properties/Sources/Payloads/Form/Form.swift#L117-L132)), which routinely comes from user- or server-supplied data.

**Failure scenario:** An app uploads a user-picked (or previously downloaded) file whose name is:

```
a"\r\nContent-Type: text/html\r\n\r\n<script>…\r\n--<boundary>\r\nContent-Disposition: form-data; name="admin"\r\n\r\ntrue
```

`contentDisposition()` splices that straight into the part headers, letting the attacker override the part's `Content-Type`, close the part early, and inject an entire extra form field (`admin=true`) that the declared `Property` tree never contained. The boundary itself is unpredictable (128 random bits, `FormGroupBuilder.swift:53-58`), but the injected `name` alone is sufficient — no knowledge of the boundary is needed to inject a header or a second field body via the bare `\r\n\r\n`.

**Fix applied:** `FormItem.contentDisposition()` now routes `name`/`filename` through a new `FormItem.escapedParameterValue(_:)` helper that percent-encodes `"` → `%22`, `\r` → `%0D`, `\n` → `%0A` before interpolation — the convention curl and browsers use for `multipart/form-data` (see the WHATWG HTML living standard's algorithm for it). See [`FormItem.swift:118-148`](Sources/RequestDL/Properties/Sources/Payloads/Form%20Group/Models/FormItem.swift#L118-L148).

One implementation subtlety worth flagging for future edits to this helper: it walks `value.unicodeScalars`, not `value` (`Character`s). A literal CRLF pair is a single `Character` in Swift (one extended grapheme cluster) — a `switch` over `Character` matching `"\r"`/`"\n"` individually would silently miss a `"\r\n"` pair entirely and let it pass through unescaped, which is exactly what an initial version of this fix did (caught by the regression test below, which deliberately uses a real `\r\n` in both `name` and `filename` rather than the two characters separately).

**Regression test:** `FormGroupTests.group_whenNameOrFilenameContainsQuoteOrCRLF_escapesInsteadOfInjectingHeaders()` in [`FormGroupTests.swift`](Tests/RequestDLTests/Properties/Sources/Payloads/Form%20Group/FormGroupTests.swift) builds a `Form` with the injection payload from the failure scenario above in both `name` and `filename`, parses the resulting multipart body with the test-only `MultipartFormParser`, and asserts: exactly one part is produced (not two, i.e. no injected extra field), its `Content-Disposition` header is the fully-escaped single line, and its `Content-Type`/`Content-Length`/contents are the legitimate, un-tampered-with values. Verified passing on both the default (NIO) and `--disable-default-traits` (portable) trait configurations, alongside the full existing `FormTests`/`FormGroupTests` suites.

---

## 2. TLS pinning / trust roots dropped after a cross-host redirect (`.urlSession` only)

**Category:** Security · **Verdict:** CONFIRMED · **Status: FIXED**

**Locations:**
- [`Internals.URLSessionClient.TLSDelegate.swift:53-56`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Identity/Internals.URLSessionClient.TLSDelegate.swift#L53-L56)
- [`Internals.URLSessionClient.swift:154-156`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Internals.URLSessionClient.swift#L154-L156)

```swift
guard challenge.protectionSpace.host == host else {
    completionHandler(.performDefaultHandling, nil)
    return
}
```

`host` is captured once, from the **initial** `request.url?.host`. The same `TaskDelegate` instance serves the entire redirect chain (redirects are followed in-task via `willPerformHTTPRedirection`, `Internals.URLSessionClient.swift:757-836`). On the NIO backends the equivalent hooks are installed at `HTTPClient.Configuration` level ([`Internals.Session.Configuration.swift:119-124`](Sources/RequestDLInternals/Sources/Session/Configuration/Internals.Session.Configuration.swift#L119-L124)), so they apply uniformly to every connection the client opens, redirect targets included — this is a `.urlSession`-only gap.

**Failure scenario:** A session pins `api.example.com`'s SPKI with `tlsPinningPolicy == .strict`. `api.example.com` returns `302 Location: https://evil.example/…`. URLSession opens a new TLS connection to `evil.example`; `TLSDelegate` observes `protectionSpace.host != "api.example.com"` and answers `.performDefaultHandling`, so the pin — and any configured `trustRoots` / `additionalTrustRoots` / `revocationPolicy` — is never applied, and the connection is accepted on system trust alone. The identical request under `.requiredExecutor(.nio)` correctly rejects it. (`request.url?.host == nil` takes the same skip path via the `flatMap` at line 154-156.) The divergence is hinted at in `TLSDelegate`'s own comment but is not surfaced anywhere in the public `SecureConnection` documentation.

**Fix applied:** Split what the host check gates. `Internals.URLSessionIdentityPolicy.handle(challenge:completionHandler:)` gained an `isConfiguredHost: Bool` parameter ([`Internals.URLSessionIdentityPolicy.swift:96-131`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Identity/Internals.URLSessionIdentityPolicy.swift#L96-L131)): server-trust challenges (pinning, trust roots, revocation, hostname-verification overrides) are now evaluated through `serverTrustPolicy` **unconditionally**, `isConfiguredHost == false` included, matching `.nio`'s always-on behavior; only the client-certificate credential stays gated to `isConfiguredHost == true`, since presenting an mTLS identity to an unexpected redirect target is a separate, legitimate thing to keep guarding against. `TLSDelegate.urlSession(_:task:didReceive:completionHandler:)` ([`Internals.URLSessionClient.TLSDelegate.swift:47-59`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Identity/Internals.URLSessionClient.TLSDelegate.swift#L47-L59)) now always calls `policy.handle(...)`, passing `challenge.protectionSpace.host == host` as `isConfiguredHost` instead of short-circuiting to `.performDefaultHandling` before `policy` is ever consulted.

**Suggested fix direction (superseded by the above):** ~~Re-evaluate pinning/trust configuration per-host on every `URLAuthenticationChallenge` the delegate receives, not just the request's original host — or refuse to follow cross-host redirects at all when pinning/custom trust is configured, matching the `.nio` behavior.~~

---

## 3. `revocationPolicy` / `trustDecisionObserver` silently dropped on the NIOSSL path

**Category:** Security · **Verdict:** CONFIRMED · **Status: FIXED**

**Location:** [`Internals.SecureConnection.swift:275-289`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.SecureConnection.swift#L275-L289)

```swift
let hasPins = !(tlsPins ?? []).isEmpty
return .init(
    tlsConfiguration: tlsConfiguration,
    tlsCustomVerification: hasPins ? trustEvaluator?.tlsCustomVerification : nil,   // <-- gate
    tlsCustomVerificationNetworkFramework: trustEvaluator?.tlsCustomVerificationNetworkFramework,
    …
)
```

`Internals.NIOTrustEvaluator.resolve(from:)` ([`Internals.NIOTrustEvaluator.swift:60-111`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.NIOTrustEvaluator.swift#L60-L111)) does build an evaluator whenever `revocationPolicy != nil` or `observer != nil` on Darwin, and `DarwinTrustEvaluation.prepare` ([`Internals.DarwinTrustEvaluation.swift:100-125`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.DarwinTrustEvaluation.swift#L100-L125)) is what appends `SecPolicyCreateRevocation`. But the `hasPins` gate means that evaluator is only ever attached to the **Network.framework** hook, never the **NIOSSL** hook. The doc comment at `Internals.SecureConnection.swift:35-37` states the opposite (that `revocationPolicy` and `trustDecisionObserver` "still route through it on `.nio` as well"), as does [`TrustDecisionObserver.swift:9-13`](Sources/RequestDLInternals/Sources/Secure%20Connection/Models/TrustDecisionObserver.swift#L9-L13).

**Failure scenario:**

```swift
Session().secureConnection {
    SecureConnection()
        .cipherSuites("TLS_AES_256_GCM_SHA384")
        .revocationPolicy(.strict)
}
```

on macOS/iOS. `cipherSuites` makes the configuration incompatible with both `.urlSession` and Network.framework, so `resolveExecutor()` returns `.nio` ([`Internals.Session.Configuration.swift:343-392`](Sources/RequestDLInternals/Sources/Session/Configuration/Internals.Session.Configuration.swift#L343-L392)) and the connection runs over NIOSSL/BoringSSL. `tlsPins` is empty, so `tlsCustomVerification` is `nil`: `SecPolicyCreateRevocation(… | kSecRevocationRequirePositiveResponse)` is never installed, and a **revoked** peer certificate is accepted while the caller believes strict OCSP/CRL enforcement is active. The same gate silences `trustDecisionObserver`, so security-audit logging records nothing for those connections. This also affects `.nioTransportServices` whenever a proxy forces the NIOSSL fallback.

**Fix applied:** `hasPins` was renamed `needsNIOSSLCustomVerification` and its condition extended to `!(tlsPins ?? []).isEmpty || revocationPolicy != nil || trustDecisionObserver != nil` ([`Internals.SecureConnection.swift:268-290`](Sources/RequestDLInternals/Sources/Secure%20Connection/Secure%20Connection/Internals.SecureConnection.swift#L268-L290)), so the NIOSSL-facing `tlsCustomVerification` is attached whenever any of the three settings NIOSSL has no native equivalent for is configured, exactly as the type's own doc comment already claimed. `additionalTrustRoots`/`.noHostnameVerification`-only configurations correctly remain ungated here, since NIOSSL still honors both natively via `TLSConfiguration` with no assist needed. The doc comment at the top of the type was also corrected — it previously said the gate "stays gated to pins only," which is no longer accurate.

**Regression coverage:** `RequestConfigurationURLSessionClientTests`/`InternalsServerTrustPolicyTests` (30 tests covering pinning, trust roots, and observer notification) pass unchanged on the default (NIO) trait after this fix, confirming no existing pinning/trust-root behavior regressed. A dedicated test exercising `revocationPolicy` actually reaching NIOSSL was not added — doing so needs a revoked certificate fixture and OCSP/CRL responder, out of scope for this pass; the fix itself is a narrow, mechanical widening of an existing, already-tested condition.

---

## 4. Buffer/cache files created world-readable (0644) — NIO backend only

**Category:** Security · **Verdict:** CONFIRMED · **Status: FIXED**

**Locations:**
- [`URL+Extensions.swift:112-115`](Sources/RequestDLInternals/Extensions/URL+Extensions.swift#L112-L115) — `openFile(forWritingAt:options: .newFile(replaceExisting: false))` with no `permissions:` argument.
- [`Internals.Buffer.swift:189-204`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Internals.Buffer.swift#L189-L204), [`:277-284`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Internals.Buffer.swift#L277-L284) — `Storage.write` calls `_createResourceIfNeeded()` (the above) before opening `_outputStream`.
- [`Internals.FileStreamBuffer.swift:110-117`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Models/Internals.FileStreamBuffer.swift#L110-L117) — the intended `permissions: .ownerReadWrite` is passed to `.modifyFile(createIfNecessary: true, …)`, which is a no-op because the file already exists by then.
- [`DiskStorage.swift:671-674`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L671-L674) — `writeAndClose` (`response.record`) likewise passes no permissions.

`NIOFileSystem`'s default for a new file is `FilePermissions.defaultsForRegularFile == [.ownerReadWrite, .groupRead, .otherRead]` (0o644) — see `swift-nio`'s `Sources/_NIOFileSystem/OpenOptions.swift:285-289`. The portable (`--disable-default-traits`) mirror at [`Internals.PortableFileSystem.swift:292-316`](Sources/RequestDLInternals/Sources/File%20System%20Manager/Internals.PortableFileSystem.swift#L292-L316) creates with 0o600 — the two backends disagree. Cache directories go through `createDirectory` → `defaultsForDirectory` (0o755).

**Failure scenario:** On Linux (server-side Swift, containers, CI), a request body too large to keep in memory spills to `Internals.FileBufferURL.temporaryURL` under `/tmp` ([`FileBufferURL.swift:37-43`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Models/FileBufferURL.swift#L37-L43)). That file — containing the full request body, e.g. a JSON payload with a bearer token or a multipart upload — is created mode 0644 and lives until the owning `Buffer.Storage` deinitializes. Any other local UID can read it. The same applies to cached `data.record` / `response.record` under `FilePath.cachesDirectory`, where `response.record` holds the full response header set (`Set-Cookie` included). Disabling the `NIOTransport` trait changes the mode to 0600, so this exposure exists only in the default build.

**Fix applied:** `permissions: .ownerReadWrite` is now passed explicitly at all four NIO-path `.newFile(...)` call sites — [`URL+Extensions.swift:114`](Sources/RequestDLInternals/Extensions/URL+Extensions.swift#L114) (`createPathIfNeeded()`) and [`:161`](Sources/RequestDLInternals/Extensions/URL+Extensions.swift#L161) (`write(_:)`), [`Internals.FileBufferURL.swift:122`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Models/Internals.FileBufferURL.swift#L122) (`truncate()`), and [`DiskStorage.swift:673`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L673) (`writeAndClose`, i.e. `response.record`). `Internals.Buffer.swift`'s two cited call sites needed no direct edit: both route through `_createResourceIfNeeded()` → `URL.createResourceIfNeeded()` → `URL.createPathIfNeeded()`, so fixing that one call chain covers them.

To keep the portable backend's call-site syntax identical (a documented goal of `PortableFileSystem.WriteOptions`, letting most call sites compile unchanged against whichever backend `Internals.fileSystem` resolves to), `PortableFileSystem.WriteOptions.newFile` gained a matching, *required* `permissions: FilePermissions` parameter (no default — mirroring `.modifyFile`'s existing convention of requiring it explicitly, rather than silently defaulting the way `NIOFileSystem`'s own `permissions: FilePermissions? = nil` does). Its implementation now honors that parameter (`attributes: [.posixPermissions: permissions.rawValue]`) instead of a hardcoded `0o600` literal — no behavior change there since every call site already passes `.ownerReadWrite`, but the value is no longer duplicated as a second source of truth. See [`Internals.PortableFileSystem.swift:48-70, 296`](Sources/RequestDLInternals/Sources/File%20System%20Manager/Internals.PortableFileSystem.swift#L48-L70).

**Regression test:** Two new tests in [`URLExtensionsTests.swift`](Tests/RequestDLInternalsTests/Extensions/URLExtensionsTests.swift) — `writeCreatesAFileWithOwnerOnlyPermissions()` and `createPathIfNeededCreatesAFileWithOwnerOnlyPermissions()` — `stat(2)` the file each API creates and assert `st_mode & 0o777 == 0o600`, independent of either backend's own bookkeeping (neither `Internals.fileSystem`'s `FileInfo` nor `PortableFileSystem.Info` surfaces permissions at all). Verified passing on both trait configurations, alongside the full existing `URLExtensionsTests`/`InternalsFileBufferURLTests`/`DiskStorageTests` suites (7 + 15 tests respectively, both traits).

---

## 5. `IdentityManager.release` may delete Keychain items belonging to a newer handle

**Category:** Security · **Verdict:** CONFIRMED (upgraded from PLAUSIBLE — see reasoning below) · **Status: FIXED**

**Location:** [`Internals.IdentityManager.swift:56-93`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Identity/Internals.IdentityManager.swift#L56-L93)

`release(label:)` does `live[label] = nil` and calls `SecItemDelete` unconditionally. It never checks whether the registry entry still points at *this* handle before deleting — contrast the guarded-removal pattern `DiskStorage.Index.remove(_:ifLocation:)` uses for exactly this kind of race ([`DiskStorage.swift:228-234`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L228-L234)). Because Swift zeroes weak references before/at deinitialization, `handle(for:)`'s `live[label]?.value` can return `nil` while the old handle's `deinit` is still queued on the lock.

**Failure scenario:** Thread 1 releases the last reference to `IdentityHandle` A (a pooled `URLSessionClient` being recycled by `ClientManager.cleanupIfNeeded`); `A.deinit` → `release(label:)` blocks on the lock. Thread 2 concurrently builds a new `URLSessionIdentityPolicy` for the same certificate/key pair, wins the lock, observes the zeroed weak reference, re-runs `build()` (re-adding `kSecClassKey`/`kSecClassCertificate`), registers handle B, and releases the lock. Thread 1 then proceeds: it clears B's registry entry and `SecItemDelete`s both Keychain items that B's `SecIdentity` was just built from. The next mTLS handshake using B fails to sign (an `errSecItemNotFound`-class failure from the now-unbacked key), and every subsequent `handle(for:)` call re-adds and re-deletes the pair, churning the Keychain.

**Why this is CONFIRMED, not just PLAUSIBLE:** Swift's documented `weak var` semantics zero the reference as soon as an object's strong refcount hits zero — specifically to prevent "resurrection" through a weak load — which happens *before* that object's `deinit` body (here, the call into `release(label:)`) gets a chance to even ask for `IdentityManager`'s lock. That zeroing is a runtime-level operation on the weak side table, entirely independent of `lock`. So the ordering "one Keychain round trip always finishes before the next begins" (true, since `handle(for:build:)` and `release(label:)` share `lock`) does not prevent the bug: it only decides which of the two *already-inevitable* orderings happens, and the harmful one (a fresh build's registration finishing, then the dying handle's stale release running after it) is exactly as reachable as the safe one under that same lock, since the weak-zeroing that makes the stale release proceed at all happens outside the lock's reach.

**Fix applied:** `release(label:)` now checks `live[label]?.value == nil` (under the same lock it already held) before clearing the registry slot or touching the Keychain — see [`Internals.IdentityManager.swift:74-93`](Sources/RequestDLInternals/Sources/Client/URLSession%20Client/Identity/Internals.IdentityManager.swift#L74-L93). If a newer handle has already been registered for the label by the time a stale release runs, that check is non-nil and the stale release does nothing, leaving both the registry and the Keychain items to the newer handle's own eventual release. The type's own doc comments (on `IdentityManager` and on `release(label:)`) were expanded to explain the actual race, not just the (true but insufficient) lock-ordering guarantee.

**Regression test — and an honest limitation of it:** [`InternalsIdentityManagerTests.swift`](Tests/RequestDLInternalsTests/Sources/Client/URLSession%20Client/Identity/InternalsIdentityManagerTests.swift) hammers `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)` (the real production entry point into `IdentityManager`, using real certificate/key fixtures so every call resolves to the same content-derived label) with 20 concurrent tasks × 25 build/release cycles each, then confirms one more build still succeeds. This test was run, unmodified, against the *pre-fix* code (fix temporarily set aside, then restored) three times and **passed every time** — it does not reliably reproduce the race. Two things explain that without undermining the fix's justification above: the window between a handle's weak-zeroing and its `release(label:)` actually acquiring the lock is minute next to a Keychain round trip, and even a hit is self-healing here, since the very next `makeIdentity` call for the label just re-adds whatever a stale release wrongly deleted, through the ordinary "not found, so add it" path — leaving no externally visible symptom in a workload that (like this test's, and like real pooled-client reuse) keeps rebuilding for the same label. The test is kept as a general concurrency-safety smoke test (no crash, every build keeps succeeding under heavy churn), with its own doc comment stating plainly that it does not prove the fix closes this specific race — that argument rests on Swift's documented ARC semantics, laid out in `IdentityManager`'s own doc comments, not on this test.

**Suggested fix direction (superseded by the above):** ~~Only delete on release if the registry still maps `label` to the handle being released (identity-compare, not just presence), mirroring `DiskStorage.Index.remove(_:ifLocation:)`.~~

---

## 6. Unbounded PAC proxy cache + one OS thread per cache miss

**Category:** Availability · **Verdict:** CONFIRMED · **Status: FIXED**

**Locations:**
- [`Internals.PACProxyCache.swift:41`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACProxyCache.swift#L41), [`:59-84`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACProxyCache.swift#L59-L84), [`:94-97`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACProxyCache.swift#L94-L97) — `storage: [Key: Entry]` keyed by `(scriptURL, full targetURL)` on a process-wide `shared` actor. Entries expire logically (`isExpired`) but are never removed; there is no ceiling and no sweep.
- [`Internals.PACEvaluator.swift:63-78`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACEvaluator.swift#L63-L78) — one dedicated `Thread` per uncached evaluation, blocked in `CFRunLoopRunInMode` for up to `evaluationTimeout = 30`s.
- The `await` at `PACProxyCache.swift:69` is an actor suspension point, so N concurrent misses on the same key all proceed to evaluate independently (no dedup).

Contrast with `Internals.Storage` ([`Internals.Storage.swift:54-60`](Sources/RequestDLInternals/Sources/Storage/Storage/Internals.Storage.swift#L54-L60), [`:231-250`](Sources/RequestDLInternals/Sources/Storage/Storage/Internals.Storage.swift#L231-L250)), which deliberately bounds itself at `maximumCount = 256` with `_evictIfNeeded()`.

**Failure scenario:** A long-lived iOS/macOS app on a corporate network with a PAC file configured, using `SystemProxy()`. `Resolve.sessionConfiguration(for:)` ([`Resolve.swift:89-91`](Sources/RequestDL/Properties/Sources/Graph/Resolve/Resolve.swift#L89-L91)) calls the resolver once per request with the **full** request URL, so every distinct URL (including query strings) adds a permanent dictionary entry — a feed view loading thousands of distinct image URLs grows the singleton's dictionary without bound for the life of the process. Separately, a screenful of 100 images loading at once produces 100 simultaneous cache misses, hence 100 OS threads (256 KiB stack each), each potentially blocked up to 30s if the PAC server is slow or unreachable.

**Fix applied:** Two of the three suggested changes; the key-granularity change was deliberately **not** made (see below).

- **Eviction ceiling** ([`Internals.PACProxyCache.swift:39-53, 145-161`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACProxyCache.swift#L39-L53)): `maximumCount = 256`, mirroring `Internals.Storage.maximumCount`/`_evictIfNeeded()` almost verbatim — same ceiling value, same "drop to three quarters, oldest first" batching, same rationale (sorting is linearithmic, so evicting one entry per write would make a table at the ceiling pay a full scan on every miss). `maximumCount` is an instance property (default from the static constant, overridable via `init`), matching `Internals.Storage`'s own pattern, specifically so a test can exceed a *small* cap instead of needing hundreds of real PAC evaluations to exceed 256.
- **Concurrent-miss dedup** ([`:70-132`](Sources/RequestDLInternals/Sources/Session/Proxy/Internals.PACProxyCache.swift#L70-L132)): a new `inFlight: [Key: Task<Internals.Proxy?, Never>]` tracks one evaluation per key. A miss checks `inFlight[key]` before starting a new evaluation; if one is already running, the caller awaits that same `Task` instead of starting its own. This directly closes the reentrancy window the finding described: `proxy(forScriptURL:targetURL:)` awaits `Internals.PACEvaluator.evaluate(...)`, a genuine suspension point, so without this a burst of concurrent requests to the same host each saw the same cache miss and opened their own dedicated `Thread` in `Internals.PACEvaluator`.
- **Key granularity — not changed:** the suggested `(scriptURL, host)` key would reduce cardinality, but a PAC script's `FindProxyForURL(url, host)` receives the full URL and is free to branch on path/query, not just host (unusual, but within the PAC spec) — narrowing the key risks silently reusing a stale routing decision for a different path on the same host, a correctness regression the audit's own "availability" framing didn't call for. The ceiling above already closes the "unbounded" gap on its own, without that risk.

**Regression tests:** two new tests in [`InternalsPACProxyCacheTests.swift`](Tests/RequestDLInternalsTests/Sources/Session/Proxy/InternalsPACProxyCacheTests.swift):

- `proxy_whenEntryCountExceedsMaximum_evictsTheOldestRatherThanGrowingWithoutBound()` — six real evaluations against a `PACProxyCache(maximumCount: 4)`, asserting `cache.count <= 4` afterward.
- `proxy_whenManyConcurrentCallsMissTheSameKey_evaluatesOnlyOnce()` — twenty concurrent misses for one key against a deliberately slow-to-respond local PAC server, asserting `cache.evaluationCount == 1` afterward.

Both `count` and `evaluationCount` are new, `package`-internal, test-only accessors. Counting real TCP connections was tried first for the second test and abandoned: empirically, `CFNetworkExecuteProxyAutoConfigurationURL` caches a script's fetched content internally (confirmed by observing that a second, independent `PACProxyCache` instance evaluating a *different* target URL against the *same* script cost zero additional connections), so connection counts can't distinguish "one shared evaluation" from "many independent ones" that all happen to hit that OS-level cache. `evaluationCount` — incremented exactly where a genuinely new evaluation `Task` is created — has no such confound. Both new tests were confirmed to actually catch their respective bugs: each was run against the fix with the relevant code path (`_evictIfNeeded`-equivalent / the `inFlight` check) temporarily disabled, and failed as expected; restoring the fix made them pass again.

---

## 7. Cache directory scan stalls 15s per incomplete entry

**Category:** Availability · **Verdict:** CONFIRMED · **Status: FIXED**

**Locations:**
- [`DiskStorage.swift:63-82`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L63-L82), [`:133-135`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L133-L135) — `Record.init?(_ url:)` calls `isReachableWithRetry` for **both** `response.record` and `dataURL` unconditionally, no short-circuit.
- `retryingUntilSuccess` defaults to `attempts: 300, retryDelay: 50_000_000` — a 15s budget per missing file.
- [`:390-406`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L390-L406), [`:780-799`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L780-L799) — `records()` runs `Record(entryURL)` over **every** `.cached` entry in the directory, serially.

The retry budget's own doc comment (`:124-132`) justifies the 15s window for "a file written and closed right before this runs" — true for the by-key read path, but not for a full directory scan. Crucially, `data.record` does not exist between `allocateBuffer` returning and the first body byte arriving: `Internals.FileBuffer` opens lazily, and the pre-creation in `applyFileProtection(to:)` (`:696-722`) only runs when `fileProtection` is set, and is skipped entirely on simulators.

**Failure scenario:** Request A is streaming a large cacheable body (its record directory exists, `data.record` does not yet). The app calls `await DataCache.shared.removeAll()` → `freeSpace(.zero)` → `records()` → `Record(A's url)` → 300 × 50ms retrying on `dataURL`. The caller's `await` hangs for 15s for one in-flight write, and 15s × N for N such entries (a burst of image loads makes N large). The same stall hits `removeAll(since:)` and every `freeSpace` rescan (`:577-614`); `DataCache.discardFailedWrite`'s own doc (`DataCache.swift:593-606`) already names this cost for orphaned directories.

**Fix applied:** `Record.init?(_ url:)` gained a `retryOnMiss: Bool = true` parameter ([`DiskStorage.swift:64-99`](Sources/RequestDL/Properties/Sources/Cache/Data%20Cache/Models/DiskStorage.swift#L64-L99)): `false` skips straight to a single, non-retried `url.isReachable` check for both files. The two checks were also changed from unconditional to short-circuiting (`guard await isReachable(responseURL), await isReachable(dataURL) else { return nil }`), so a genuinely-missing `response.record` no longer also pays `dataURL`'s own retry budget only to discard the result — halving the worst case for the by-key path too.

`records()` — the full directory scan `freeSpace`/`removeAll(since:)` call — itself gained a matching `retryOnMiss: Bool = true` parameter, forwarded straight to each `Record.init?`. Both eviction call sites (`removeAll(since:)` and `freeSpace(_:)`) now pass `retryOnMiss: false`. `record(forKey:)`'s own cold-lookup fallback (`index.location(for:scan:)`, used the *first* time a not-yet-indexed key is looked up) keeps the default `true` — that path exists specifically to find a record that may have been written only moments ago, so retrying a transient miss there is exactly the right thing to keep doing.

This last point surfaced during verification, not from the original audit read: `records()` is not exclusively a bulk-eviction helper — `record(forKey:)` reuses it as its cold-scan fallback, a path that genuinely needs the retry (confirmed by an existing test, `diskStorage_whenDataRecordAppearsShortlyAfterResponseRecord_shouldStillFindRecord`, which broke under an earlier, cruder version of this fix that removed the retry from `records()` unconditionally). The final fix distinguishes the two call sites instead of changing `records()`'s behavior wholesale.

**Regression test:** `removeAll_whenAnEntryIsStillBeingWritten_doesNotStallWaitingForItToComplete()` in [`DiskStorageTests.swift`](Tests/RequestDLTests/Properties/Sources/Cache/Data%20Cache/Models/DiskStorageTests.swift) hand-creates a record directory with `response.record` present and `data.record` deliberately never created (the exact shape of an in-progress write), calls `removeAll()`, and asserts it completes in under 2 seconds. Confirmed to actually catch the regression: temporarily reverting just the two `retryOnMiss: false` call sites back to the default made this test fail after ~16.3s (matching the 15s retry budget) before being restored to green.

---

## 8. SSE parser: unbounded line buffer + quadratic rescan

**Category:** Availability · **Verdict:** CONFIRMED · **Status: PARTIALLY FIXED** (quadratic rescan closed; unbounded buffer left as a deliberate scope decision, see below)

**Location:** [`ServerSentEventParser.swift:61-97`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Download/Server-Sent%20Events/Models/ServerSentEventParser.swift#L61-L97)

`lineBuffer.append(chunk)` grows with no ceiling. When no `\r`/`\n` is found, `searchIndex` stays at `startIndex`, so `lineBuffer.removeSubrange(startIndex..<searchIndex)` (`:95`) removes nothing, and the **next** `feed` call re-scans the whole accumulated buffer from byte 0 via `lineBuffer[searchIndex...].firstIndex(where:)` (`:77-79`).

**Failure scenario:** A `text/event-stream` endpoint (malicious, or simply buggy — a `data:` line assembled from a large blob) emits 200 MB before its first newline. The client accumulates all 200 MB in `lineBuffer` (on top of the `DownloadBuffer` chunks), and with 1 KiB chunks (the default `.length(1_024)` reading mode, [`RequestConfiguration.swift:118`](Sources/RequestDL/Request/RequestConfiguration.swift#L118)) performs roughly 200,000 full-buffer rescans — Σ i·1 KiB ≈ 2×10¹⁰ byte comparisons — pegging a CPU core before the first event is ever delivered. No cap, no error is raised; the parser simply never yields.

**Fix applied — the quadratic rescan:** `extractLines(from:)` now tracks `scannedPrefixLength`, how many leading bytes of `lineBuffer` have already been confirmed (by an earlier `feed(_:)` call) to hold no terminator, and resumes *searching* from there rather than from `lineBuffer.startIndex` every time ([`ServerSentEventParser.swift:61-108`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Download/Server-Sent%20Events/Models/ServerSentEventParser.swift#L61-L108)). Total scanning work across the life of one line is now linear in its length, not quadratic in how many chunks it arrived in.

The subtlety that surfaced while implementing this: *where to resume searching* and *where the current line's content starts* are not the same position once a line spans more than one `feed(_:)` call. A first attempt reused one index (`searchIndex`) for both, which is correct only when a line is fully contained in a single call (matching every existing test at the time) — for a line split across calls, it silently truncated the extracted content down to just the bytes received in the *last* call, dropping everything from earlier calls. An existing test, `feed_whenLineIsSplitAcrossChunks_shouldStillEmitEvent`, caught this immediately once run (not left latent): the fix now keeps `lineStart` (content) and `searchStart` (resume position) as two separate indices, converging back to the same value once a terminator is actually found and consumed.

**Left open — the unbounded buffer:** deliberately not adding a maximum-line-length cap. This codebase has no existing precedent for an arbitrary byte-size ceiling on buffered content anywhere else (`readToEnd(maximumSizeAllowed:)` is called with `.unlimited` at every call site in `Sources/`); introducing one solely for SSE `data:` lines would be a one-off, undiscussed behavior change with a real (if narrow) correctness cost of its own — a legitimate large SSE payload (e.g., a base64-encoded image pushed as one `data:` line, unusual but not against the spec) would need to pick a number to fail at. With the quadratic rescan gone, the concrete, measurable harm this finding described (a CPU core pegged before the first event is delivered) no longer applies; what remains is an unbounded-*memory* concern proportional to how large a single line a server actually sends, which is a scope/API-design question (truncate silently? make `feed` throw? cap only past some very generous threshold?) rather than a bug fix, and is left for a follow-up if the maintainers want a specific policy here.

**Regression test:** `feed_whenOneLineArrivesAcrossManySmallChunks_scalesLinearlyAndKeepsTheWholeLine()` in [`ServerSentEventParserTests.swift`](Tests/RequestDLTests/Tasks/Sources/Raw%20Task/Download/Server-Sent%20Events/Models/ServerSentEventParserTests.swift) feeds one ~300 KB line across 3,000 small chunks and asserts both that the full content survives intact (catching the truncation bug described above) and that it completes in under 2 seconds. Confirmed against the pre-fix code: the identical test took 6.96 seconds against the original quadratic implementation (a ~600x difference) and correctly failed the timing assertion.

---

## 9. HTTP disk cache never hits for responses without `Content-Length`

**Category:** Integrity · **Verdict:** CONFIRMED · **Status: FIXED**

**Location:** [`Internals.CacheControl.swift:448-471`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Cache%20Control/Internals.CacheControl.swift#L448-L471), [`:498-502`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Cache%20Control/Internals.CacheControl.swift#L498-L502)

```swift
let contentLength = contentLength(headers: headers["Content-Length"] ?? [])
if cachedData.buffer.readableBytes != contentLength { return false }
…
private func contentLength(headers: [String]) -> Int {
    directives(headers).compactMap(Int.init).max() ?? .zero   // 0 when the header is absent
}
```

`makeCachedSession` (`:174-204`) treats a `false` result as "stale": it calls `dataCache.remove(forKey:)` and returns `nil`. Nothing upstream prevents such a response from being cached in the first place — `cacheIfNeeded` (`:371-446`) passes `contentLength: 0` to `allocateBuffer`, which happily allocates and writes.

**Failure scenario:** A cacheable `GET` (`.cachePolicy([.disk])`, no body) to a server that responds `Transfer-Encoding: chunked` with no `Content-Length` — i.e. any streamed/dynamically generated response, and most HTTP/2 responses. The full body is written to `data.record` plus `response.record`, costing disk I/O and space. On the next identical request, `isCachedDataValid` compares `readableBytes` (say 40,000) against `contentLength` (0), returns `false`, deletes the entry, and falls through to the network — the cache is permanently 0%-hit for these responses while still paying the full write cost every time. The same mismatch fires for a `Content-Encoding: gzip` response on `.nio`: `NIOHTTPResponseDecompressor` decodes the body before it reaches the cache tee but leaves the compressed `Content-Length` in the head (acknowledged at `Internals.Client.swift:214-217`), so cached bytes and declared length never agree.

**Fix applied:** `contentLength(headers:)` now returns `Int?` instead of `Int` ([`Internals.CacheControl.swift:498-505`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Cache%20Control/Internals.CacheControl.swift#L498-L505)) — `nil` for "no `Content-Length` directive present at all," distinct from a genuine `Content-Length: 0`, a distinction the old `?? .zero` fallback erased. `isCachedDataValid` ([`:450-472`](Sources/RequestDL/Tasks/Sources/Raw%20Task/Cache%20Control/Internals.CacheControl.swift#L450-L472)) now only runs the byte-count check when `contentLength` is non-nil *and* the cached response has no `Content-Encoding` header — the second condition closes the audit's other named case (a transparently-decompressed body compared against a `Content-Length` that still reflects the pre-decompression, compressed size on the wire; `Internals.Client.swift` already documents that this header survives decompression under both `.nio` and `.urlSession`). The one other caller of `contentLength(headers:)` (`cacheIfNeeded`'s capacity-hint use, where `0` was always a fine stand-in for "unknown") was updated to `?? 0` to keep that behavior unchanged.

This does give up the check's only defense against a response body that was genuinely truncated by something other than a stream error the write path's own error handling already discards (the write task's `catch` block calls `discardFailedWrite` for any stream failure/cancellation; what's left is the process dying mid-write before that ever runs) — accepted deliberately, as the better trade against every chunked-transfer or compressed response permanently missing the cache, which is what the unconditional check did instead.

**Regression tests:** two new tests in [`CachedRequestTests.swift`](Tests/RequestDLTests/Properties/Sources/Cache/Cached%20Request/CachedRequestTests.swift), each seeding the cache directly via `mockCachedData`/`setCachedData` (bypassing the network round trip, so the response headers are controlled precisely) and confirming `.returnCachedDataElseLoad` serves the seeded entry rather than treating it as stale:

- `cache_whenCachedResponseHasNoContentLength_isStillValid()` — no `Content-Length` header at all.
- `cache_whenCachedResponseHasContentEncoding_isStillValidDespiteContentLengthMismatch()` — `Content-Encoding: gzip` present alongside a deliberately mismatched `Content-Length`.

`mockCachedData` gained an `includeContentLength: Bool = true` parameter to support the first case. The first test was confirmed against the pre-fix code (fix temporarily set aside, then restored) and failed with exactly the two expected assertions broken; the second test exercises a code path (`Content-Encoding` gating) that has no pre-fix equivalent to compare against; both pass with the fix applied, on the default trait (portable-trait `CachedRequestTests` hit the same pre-existing local Keychain flakiness documented earlier in this report — `OSStatus -25300` on every test in the suite, unrelated to this fix).

---

## 10. `ReadingMode(length: 0)` silently discards the entire response body

**Category:** Integrity · **Verdict:** CONFIRMED · **Status: FIXED**

**Location:** [`Internals.DownloadBuffer.swift:111-133`](Sources/RequestDLInternals/Sources/Stream/Download/Internals.DownloadBuffer.swift#L111-L133)

```swift
let availableBytes = length - currentBytes            // 0 when length == 0
let readableBytes = receivedBytes > availableBytes ? availableBytes : receivedBytes   // 0
if let data = await incomeBytes.readData(readableBytes) { … } else { break }
```

`Internals.Buffer.readData(0)` returns `nil` ([`Internals.Buffer.swift:580-589`](Sources/RequestDLInternals/Sources/Buffers/Buffer/Internals.Buffer.swift#L580-L589) → `FileStreamBuffer.readData` / `ByteStreamBuffer`'s `guard length > .zero`), so the loop `break`s on its very first iteration having consumed zero bytes. Every chunk is dropped; `_close()` then finds `readableBytes == 0` and emits nothing. The public constructor `ReadingMode(length: Int)` ([`ReadingMode.swift:43-45`](Sources/RequestDL/Properties/Sources/Headers/Reading%20Mode/ReadingMode.swift#L43-L45)) has no validation. Negative values take the same path via `Buffer.readData`'s `guard length >= .zero`.

**Failure scenario:**

```swift
DataTask {
    BaseURL("api.example.com")
    ReadingMode(length: 0)
}
```

(or a computed chunk size that happens to evaluate to 0). The request succeeds, the response head arrives with e.g. `Content-Length: 4096`, the body stream closes empty, and `try await task.result()` hands back `Data()` with no error thrown. Both backends share `DownloadBuffer`, so this is executor-independent.

**Fix applied:** `ReadingMode.init(length:)` now enforces `precondition(length > 0, ...)` ([`ReadingMode.swift:38-49`](Sources/RequestDL/Properties/Sources/Headers/Reading%20Mode/ReadingMode.swift#L38-L49)) — trapping rather than clamping, matching the one existing precedent for this kind of input validation elsewhere in the codebase (`Internals.Storage.init(lifetime:maximumCount:)`'s own `precondition(maximumCount >= 1, ...)`). Confirmed this is the *only* place a non-positive length could reach `Internals.DownloadStep.ReadingMode.length(_:)`: the sole other construction site is `RequestConfiguration`'s hardcoded default (`.length(1_024)`), so validating here closes the gap completely rather than needing a second, defensive check inside `DownloadBuffer` itself.

**Regression tests:** `initWithZeroLength_traps()` and `initWithNegativeLength_traps()` in [`ReadingModeTests.swift`](Tests/RequestDLTests/Properties/Sources/Headers/Reading%20Mode/ReadingModeTests.swift) use Swift Testing's exit-test support (`#expect(processExitsWith: .failure) { ... }`, spawning a child process and asserting it does *not* exit normally) — no precedent for testing a `precondition` trap existed anywhere in this codebase before this. Each literal (`0`, `-1`) has to be written directly inside its own closure rather than parameterized via `@Test(arguments:)`, since an exit-test closure runs in a spawned child process and so cannot capture anything from the enclosing scope. Both were confirmed against the pre-fix code (temporarily reverted, then restored) and failed as expected — the un-trapped `ReadingMode(length:)` call let the child process exit normally, which is exactly the silent-misbehavior this fix closes.

---

## Suggested prioritization

1. ~~**#1, #2, #3** — all silently defeat a security control the caller explicitly configured (multipart injection, pinning bypass, revocation bypass). These should be fixed first regardless of platform/trait.~~ **Done — see each finding's "Fix applied" section above.**
2. ~~**#4** — a straightforward one-line-per-call-site fix (pass `permissions:`) with real exposure on Linux deployments.~~ **Done — see finding's "Fix applied" section above.**
3. ~~**#5** — PLAUSIBLE only; worth a targeted concurrency test... to confirm the race is real under the actual lock granularity used.~~ **Done — upgraded to CONFIRMED via Swift ARC semantics reasoning (a stress test was written but could not reliably reproduce the race itself; see the finding's own section for why). Fixed regardless, since the fix carries no behavioral downside.**
4. ~~**#6, #7, #8** — availability/DoS-shaped issues...~~ **#6, #7 done; #8's quadratic-rescan half done, its unbounded-buffer half deliberately left open — see each finding's section above.**
5. ~~**#9, #10** — integrity bugs that degrade behavior (silently) rather than crash...~~ **Done — see each finding's "Fix applied" section above.**

All ten findings from the original audit have now been addressed in one pass or another.

## Verification notes for #1-#10

- **Build:** both `swift build` (default trait) and `swift build --disable-default-traits` (portable trait) complete cleanly after all fixes.
- **Lint:** `swift format lint --strict` passes on every file touched by these fixes (pre-existing lint failures in unrelated files, present before this pass, were left untouched).
- **Targeted tests:** `FormGroupTests`/`FormTests` (34 tests, #1); `InternalsServerTrustPolicyTests`/`RequestConfigurationURLSessionClientTests`/`ClientIdentityErrorTests` (30 tests, #2/#3); `URLExtensionsTests`/`InternalsFileBufferURLTests`/`DiskStorageTests` (7 + 15 tests, #4); `InternalsIdentityManagerTests`/`InternalsRawBytesIdentityBuilderTests` (15 tests, #5); `InternalsPACProxyCacheTests`/`InternalsPACEvaluatorTests` (11 tests, #6); `DiskStorageTests` again, now 16 tests (#7); `ServerSentEventParserTests`, now 15 tests (#8); `CachedRequestTests`, now 24 tests (#9); `ReadingModeTests`, now 6 tests (#10) — all pass on the default trait, and all but #2/#3's and #9's portable runs (see below) pass on the portable trait too.
- The portable-trait run of the #2/#3 and #9 suites was blocked by a pre-existing local Keychain flakiness (`OSStatus -25300`, "item could not be found in the keychain") confirmed present in a full-suite run captured *before* any of this session's fixes as well (86 occurrences) — environmental to this machine, not a regression introduced by these changes.
- A full-repository test run (both traits) surfaced widespread `NSURLErrorTimedOut`/`HTTPClientError.connectTimeout` failures against the `LocalServer` test fixture (`localhost:888x`), spanning areas unrelated to any of these fixes (cache, redirect, streaming). This matches previously-documented local-network flakiness on this development machine and was not chased further as part of this pass.
- #9's two new tests seed the cache directly (`setCachedData`) rather than going through a real network round trip, so they were unaffected by the `LocalServer` flakiness above; only the *rest* of `CachedRequestTests` (which does exercise the local server) hit it on the portable trait.
- #10 introduced this codebase's first use of Swift Testing's exit-test support (`#expect(processExitsWith:)`) — worth a note for anyone extending `ReadingModeTests.swift` later, since exit-test closures cannot capture anything from their enclosing scope (parameterizing via `@Test(arguments:)` does not work; each case needs its own literal-valued closure).
- #5 specifically: the fix was verified by reasoning about Swift's documented ARC weak-reference semantics (see that finding's own section), not by forcing the race to reproduce — an attempt to do so (a concurrency stress test, kept in the test suite as general coverage) did not succeed even against the unfixed code, for reasons explained there.
- #6's two new tests were each confirmed to actually catch their respective bug: run against the fix with the relevant code path (eviction / `inFlight` dedup) temporarily disabled, each failed as expected, then passed again once the fix was restored — unlike #5, both of #6's regressions were straightforwardly, deterministically reproducible.
- #7's new test was likewise confirmed deterministically: reverting just its two `retryOnMiss: false` call sites made it fail after ~16.3s, matching the 15s retry budget exactly, before being restored to green (0.02s).
- #8's new test was confirmed against the pre-fix implementation directly (not just a disabled code path, since the fix is one continuous change to `extractLines(from:)`): 6.96s pre-fix vs 0.011s post-fix on the identical test. An intermediate, incorrect version of the fix was also caught along the way, by an *existing* test (`feed_whenLineIsSplitAcrossChunks_shouldStillEmitEvent`) rather than a new one — worth noting since it's a reminder that pre-existing coverage can catch a regression a new, narrowly-scoped test wouldn't have been written to look for.
