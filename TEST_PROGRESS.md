# TEST PROGRESS — RequestDL

> **Purpose:** External memory for iterative test-writing sessions with Claude Code.
> Read this file FIRST at the start of each session. Update it at the END of each session.
> This file compensates for context-window limits during long test-coverage efforts.

## 1. Overall Goal

- **Objective:** Bring `Properties/Sources/` files currently below 85% line coverage up to at least 90%, without writing trivial/dead-code tests or altering public API to ease testing. Then move to `Tasks/`, `Request/`, and `Internals/` (only via public API).
- **Testing framework:** Swift Testing ONLY (`import Testing`, `@Test`, `@Suite`) — NO XCTest
- **Coverage command:** `./Scripts/coverage.sh` (generates `coverage-report.txt` + `coverage-lines.txt` at repo root)
- **Coverage baseline:** Full-repo TOTAL (includes `.build/` deps) ~17.49% region / ~20.06% line — measured 2026-08-03, before batch 1
- **Current coverage:** Batch 1 (11 files) and batch 2 (19 files across two rounds) all raised to 100% or near-100% line coverage — see section 2/7. Only 3 `Properties/Sources/` files remain below 85%, all investigated and confirmed untestable without altering `Sources/` for testability alone (see §7). Repo-wide TOTAL not tracked (dominated by `.build/` noise; per-file diffing in section 7 is the meaningful signal).

## 2. Module Priority & Status

| Priority | Module | Status | Coverage | Notes |
|----------|--------|--------|----------|-------|
| 1 | `Properties/Sources/` | ✅ done | Batch 1 + 2 done (30 files) | Largest module, public API. Only 3 files left below 85%, all untestable without source changes (see §7). |
| 2 | `Tasks/Sources/Modifiers/` | ✅ done | Batch 3 done (3 files fixed) | All files now ≥88% region / ≥93% line. `KeyPath.swift` (93.75% region/100% line) and `StatusCode.swift` (88.89% region/96% line) left as-is — both already above the 85% floor. |
| 3 | `Tasks/Sources/Interceptors/` | ⚪ not started | — | Side-effect observers |
| 4 | `Request/` | ⚪ not started | — | `RequestConfiguration`, `RequestBody` |
| 5 | `Internals/` | ⛔ indirect only | — | Test via public API, never directly |

**Status legend:** ⚪ not started · 🔵 in progress · ✅ done · ⛔ blocked · ⚠️ needs review

## 3. Batch Tracker

### Batch 1 — Properties/ lowest-coverage files (round 1)
- **Status:** ✅ done
- **Test file(s):** see Test Files Inventory (§4)
- [x] `HeaderSeparatorKey.swift` — `.headerSeparator(_:)` default + custom separator joins same-key headers
- [x] `RequestEnvironmentValues.swift` — subscript get/set, empty/non-empty `debugDescription` (also fixed a crash bug, see §7)
- [x] `StoredObjectConfiguration.swift` — `.global` fallback when `@StoredObject` is read outside graph traversal
- [x] `Proxy.Authorization.swift` — `.basic(username:password:)` and `.bearer(tokens:)` factories
- [x] `URLEncoder.KeyContainer.swift` — `dropKey()`, `unkeyed()` (success + `.unset` error), `.alreadySet` error
- [x] `URLEncoder.ValueContainer.swift` — `unkeyed()` (success + `.unset` error)
- [x] `URLEncoderError.swift` — all three `ErrorType` cases + `description` text (bonus, found while covering the containers)
- [x] `PayloadFactory.swift` — `jsonObject(_ array:contentType:)` via `Payload(_:options:contentType:.formURLEncoded)` with a JSON array
- [x] `ReadingMode.swift` — `init<S: StringProtocol>(separator:)` overload
- [x] `CachedData.swift` — `.policy` getter, `init(response:policy:url:)` file-backed variant
- [x] `Never+Property.swift` — investigated, **skipped**: `Never.body` getter is unreachable dead code
- [x] `_PropertyModifier_Content.swift` — investigated, **skipped**: same dead-code pattern (`Never.body`)

### Batch 2 — Properties/ lowest-coverage files (round 2)
- **Status:** ✅ done
- **Test file(s):** see Test Files Inventory (§4)
- [x] `SystemProxy.swift` — `resolvesSystemProxy` flag reaches `Resolve`'s proxy-fold; explicit `Proxy` still wins over `SystemProxy()`
- [x] `FlexibleURLError.swift` / `FlexibleURLNode.swift` — `.invalidURL` (unparseable host), `.invalidHost` (empty host, e.g. `https:///path`), and the `path == "/"` edge case in `pathComponents(from:)`
- [x] `RenegotiationSupport.swift` — `.none` and `.once` cases of `build()` (only `.always` was tested)
- [x] `PropertyNamespace.swift` — `wrappedValue`'s `?? .global` fallback when read outside graph traversal (existing `NamespaceTests` only ever read it with `id` already set)
- [x] `_Container.swift` — `init(wrappedValue:)` (unreachable via any real call site — all 3 usages are `Optional` with no initial value — covered via `@testable import` direct construction)
- [x] `AcceptCharsetHeader.swift`, `DefaultTrustRoots.swift`, `Certificate.swift` — missing `neverBody` tests (pattern present in every sibling file but these three)
- [x] `MemoryStorage.swift` / `DiskStorage.swift` — `updateCached(key:cachedResponse:maximumCapacity:)` (both found/not-found branches, memory *and* disk) and `allocateBuffer`'s "entry larger than capacity" early return, all via `DataCache`-level tests (no need to touch the internal storage types directly)
- [x] Found and fixed a real bug while testing `DiskStorage.updateCached`: same-second data loss — see §7
- **Sweep (round 2, `Properties/Sources/` files still <85% after the above):**
  - [x] `_PropertyModifier_Content.swift` — **correction to batch 1**: this file's `body: Never` is NOT the same dead-code pattern as `Never+Property.swift`. `Never+Property.swift` is `extension Never: Property { var body: Never }` — literally unreachable since `Never` has zero instances. `_PropertyModifier_Content<Modifier>.body: Never` is a property on a *constructible* struct, so `assertNever(property.body)` reaches it exactly like every other `Property`'s `neverBody` test. Batch 1 conflated the two; now covered.
  - [x] `ReadingMode.swift` — same batch-1 mistake (see above): its `neverBody` test was simply missing, not dead code. Now 100%.
  - [x] `PropertyReader.swift` — same missing-`neverBody`-test pattern, found via a systematic grep for every `body: Never { bodyException() }` in `Properties/Sources/` cross-referenced against `coverage-lines.txt` for 0-execution hits (found 3 total: the two above plus this one).
  - [x] `Seed.swift` — `description` (`CustomStringConvertible`) and `next()`; new test file, no prior tests existed
  - [x] `EncodablePayloadFactory.swift` — `.array` and `default` (top-level fragment) branches of the form-urlencoded switch, via `Payload(_:contentType:.formURLEncoded)` with an `Encodable` array / scalar (only the `.object` case was tested)
  - [x] `ContentType.swift` — `hasCharsetParameter`'s true branch (`appending(charset:)` must not double-append when the caller's content type already declares one)
  - [x] `CachePolicyProperty.swift`, `CacheStrategyProperty.swift` — investigated, **skipped**: both are `private struct`s whose only uncovered line is `body: Never`; file-private access means no test file can construct an instance to call `.body` on without loosening the type's access level, which is a testability shortcut the project rule forbids
  - [x] `DataCache.Buffer.swift` — investigated, **skipped**: `readableBytes` is unused dead internal API (no call site anywhere in `Sources/`), and `writeBuffer`'s nil-guard only fires if the underlying `AnyBuffer.getBytes()` violates its own `isValidRange` invariant — not reachable without corrupting internal state

### Batch 3 — `Tasks/Sources/Modifiers/` (priority 2)
- **Status:** ✅ done
- **Test file(s):** see Test Files Inventory (§4)
- [x] `Modifiers.FlatMapError.swift` — the "transform closure succeeds, so the *original* error gets rethrown" path (`throw error` after a non-throwing `try await transform(error)`) was never exercised; both the untyped `flatMapError { }` and the typed `flatMapError(Type.self) { }` overloads had this gap
- [x] `AsyncBytes+Collect.swift` — `log(receivedBytes:)`/`log(data:)` build their `additionalMetadata` via `@autoclosure` params, several layers deep (through `Internals.TaskLogger.log` down to swift-log's own `Logger.log`); the metadata-construction lines never executed because no test ever ran with a logger whose level allowed `.debug` messages through. Fixed by using the previously-unused `Logger.withTesting(level:recorded:perform:)` helper (`Tests/RequestDLTests/Utils/TestLogHandler.swift`) at `.trace` level and asserting on captured metadata keys.
- [x] `AsyncResponse+Collect.swift` — same `@autoclosure`-metadata gap for `log(receivedStep:)`/`log(responseHead:)`, fixed the same way. Additionally, the `try Task.checkCancellation(); throw RequestFailureError()` fallback (reached when the async sequence completes without ever yielding a `.download` step) in both `collect()` and `collect(with:)` was unreachable through any real network round-trip (a completed HTTP exchange always yields a `.download` step). Covered by directly constructing an `Internals.AsyncResponse` with all three underlying streams (`upload`/`head`/`download`) closed empty via `.empty()`, wrapped in the public `AsyncResponse` via its internal init (`@testable import` — same pattern as `InternalsAsyncResponseTests.swift`'s existing `response_whenOnlyUploading_shouldReceiveParts` test, which already closes `head`/`download` without ever appending a head).
- Full suite: 888 tests passing (up from 882 pre-batch-3).

## 4. Test Files Inventory

| Test file | Mirrors source | Tests count | Last updated | Status |
|-----------|---------------|-------------|--------------|--------|
| `Tests/RequestDLTests/Properties/Sources/Extra Properties/Environment/Models/RequestEnvironmentValuesTests.swift` | `.../Environment/Models/RequestEnvironmentValues.swift` | 5 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Headers/Headers/HeadersTests.swift` | `.../Headers/Header Node/Models/HeaderSeparatorKey.swift` | 9 (+2) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Value/Stored Object/Models/StoredObjectConfigurationTests.swift` | `.../Stored Object/Models/StoredObjectConfiguration.swift` | 2 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Session/Proxy/ProxyTests.swift` | `.../Session/Proxy/Models/Proxy.Authorization.swift` | 6 (+2) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Headers/Reading Mode/ReadingModeTests.swift` | `.../Headers/Reading Mode/ReadingMode.swift` | 3 (+1) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Payloads/Payload/PayloadTests.swift` | `.../Payloads/Payload/Models/PayloadFactory.swift` | 22 (+2) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/URL/Query/Models/URLEncoderTests.swift` | `.../URL/Query/Models/URLEncoder.KeyContainer.swift`, `URLEncoder.ValueContainer.swift`, `URLEncoderError.swift` | 49 (+8) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Cache/Data Cache/Models/CachedDataTests.swift` | `.../Data Cache/Models/CachedData.swift` | 2 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Session/Proxy/SystemProxyTests.swift` | `.../Session/Proxy/SystemProxy.swift` | 3 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/URL/URL/FlexibleURLTests.swift` | `.../URL/URL/Models/FlexibleURLError.swift`, `FlexibleURLNode.swift` | 22 (+3) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Secure Connection/Secure Connection/SecureConnectionTests.swift` | `.../Secure Connection/Models/RenegotiationSupport.swift` | 19 (+2) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Value/Namespace/PropertyNamespaceTests.swift` | `.../Value/Namespace/PropertyNamespace.swift` | 1 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Value/_Container/_ContainerTests.swift` | `.../Value/_Container/_Container.swift` | 2 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Headers/Headers/Accept Charset/AcceptCharsetHeaderTests.swift` | `.../Accept Charset/AcceptCharsetHeader.swift` | 4 (+1) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Secure Connection/Trusts/DefaultTrustRootsTests.swift` | `.../Secure Connection/Trusts/DefaultTrustRoots.swift` | 2 (+1) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Secure Connection/Certificate/CertificateTests.swift` | `.../Secure Connection/Certificate/Certificate.swift` | 1 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Cache/Data Cache/DataCacheTests.swift` | `.../Data Cache/Models/MemoryStorage.swift`, `DiskStorage.swift` | 16 (+6) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Extra Properties/Modifier/Models/_PropertyModifier_ContentTests.swift` | `.../Modifier/Models/_PropertyModifier_Content.swift` | 1 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Headers/Reading Mode/ReadingModeTests.swift` | `.../Headers/Reading Mode/ReadingMode.swift` | 4 (+1) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Reader/PropertyReaderTests.swift` | `.../Extra Properties/Reader/PropertyReader.swift` | 2 (+1) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Value/Dynamic Value/Model/SeedTests.swift` | `.../Value/Dynamic Value/Model/Seed.swift` | 2 (new file) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Properties/Sources/Payloads/Payload/PayloadTests.swift` | `.../Payloads/Payload/Models/EncodablePayloadFactory.swift`, `ContentType.swift` | 28 (+4, incl. batch 1's 2) | 2026-08-03 | ✅ |
| `Tests/RequestDLTests/Tasks/Sources/Modifiers/Flat Map Error/ModifiersFlatMapErrorTests.swift` | `.../Flat Map Error/Modifiers.FlatMapError.swift` | 6 (+2) | 2026-08-04 | ✅ |
| `Tests/RequestDLTests/Tasks/Sources/Modifiers/Progress/Extensions/AsyncBytesCollectTests.swift` | `.../Progress/Extensions/AsyncBytes+Collect.swift` | 1 (new file) | 2026-08-04 | ✅ |
| `Tests/RequestDLTests/Tasks/Sources/Modifiers/Progress/Extensions/AsyncResponseCollectTests.swift` | `.../Progress/Extensions/AsyncResponse+Collect.swift` | 3 (new file) | 2026-08-04 | ✅ |

## 5. Key Decisions & Constraints

- [x] Use `resolve(_:)` helper for `Property`/`PropertyNode` tests — no real network execution
- [x] Use `TestProperty` when a valid resolvable tree is needed (wraps in `BaseURL("www.apple.com")`)
- [x] `Internals.*` tested only through public API surface
- [x] Linux-specific branches (`#if os(Linux)`, `canImport(Glibc)`) NOT covered locally — CI handles it
- [x] No trivial tests (getters, dead code) just to inflate coverage numbers — confirmed by skipping `Never.body` getters in `Never+Property.swift` and `_PropertyModifier_Content.swift` after checking `coverage-lines.txt` showed 0 executions with no reachable call site (`Never` has no instances)
- [x] A genuine correctness bug found while triaging coverage is worth fixing even though the source rule says "don't alter public code to ease testing" — that rule is about testability shortcuts, not about leaving a confirmed crash in place. Always confirm reproduction before touching `Sources/`, and get explicit user sign-off first (done via AskUserQuestion for the `RequestEnvironmentValues.debugDescription` fix).
- [x] For types with only an `internal` (non-public) init that are otherwise reached through public property wrappers/custom strategies (`StoredObjectConfiguration`, `URLEncoder.Encoder`), it's fine to either exercise them end-to-end through the public API (preferred) or construct them directly via `@testable import` when the public entry point can't reach the specific branch (e.g. `.global` fallback, `dropKey()`/`unkeyed()` only reachable from user-supplied `.custom` strategy closures).
- [x] **Before writing off a `body: Never { bodyException() }` getter as "unreachable dead code," check whether the *enclosing type* is constructible.** `extension Never: Property { var body: Never }` (in `Never+Property.swift`) is genuinely unreachable — `Never` has zero instances. But `SomeConstructibleType.body: Never` is not the same shape: any instance of `SomeConstructibleType` can have `.body` read on it, and `assertNever(property.body)` (see `Tests/RequestDLTests/Properties/Sources/Result Builder/Either/_EitherContentTests.swift`) reaches it safely via a fatalError-override shim. Batch 1 wrongly applied the `Never+Property.swift` reasoning to `_PropertyModifier_Content.swift`; batch 2 found the same missing-test gap (not dead code) in `ReadingMode.swift` and `PropertyReader.swift`. When in doubt, grep for the sibling pattern: does every other `Property` type in the same area have a `neverBody` test using `assertNever`? If yes and this one doesn't, it's a missing test, not dead code.
- [x] A `private struct` (file-private) conforming to `Property` with an uncovered `body: Never` is a *different* case from the above and genuinely cannot be tested without loosening its access level — no test file can construct an instance to call `.body` on. This is a legitimate skip (`CachePolicyProperty.swift`, `CacheStrategyProperty.swift`), not a batch-1-style mistake. The distinguishing question: can a `Tests/` file construct an instance of the type at all?
- [x] Prefer testing internal cache-tier types (`MemoryStorage`, `DiskStorage`) through the public/internal `DataCache` surface rather than constructing them directly — `DataCache`'s own internal methods (`updateCached`, `allocateBuffer`) are reachable via `@testable import` and already exercise the real locking/eviction path, so there was no need to touch `MemoryStorage`/`DiskStorage` init directly.
- [x] When a `log(...)` call's metadata lines show 0 executions in `coverage-lines.txt` despite the enclosing function itself having a high execution count, check whether the metadata parameter is `@autoclosure` (it is, all the way down through `Internals.TaskLogger.log` to swift-log's own `Logger.log`) — if so, the closure only evaluates when the logger's level admits the message's level, and the fix is a test with an appropriately-leveled logger, not a "dead code" write-off. `Tests/RequestDLTests/Utils/TestLogHandler.swift`'s `Logger.withTesting(level:recorded:perform:)` helper existed unused in the repo for exactly this; batch 3 was its first use.
- [x] For a fallback/defensive branch that real integration tests can't reach (e.g. `AsyncResponse+Collect.swift`'s `throw RequestFailureError()` when the async sequence ends without a `.download` step — never happens on a real completed HTTP round-trip), check whether the internal type can be constructed directly via `@testable import` and driven into the exact state needed, before writing it off as untestable. `Internals.AsyncStream<Element>.empty()` + `Internals.TaskSeed.withoutCancellation` made this straightforward for `AsyncResponse`/`AsyncBytes` (both only have internal inits) — same category as the `StoredObjectConfiguration`/`MemoryStorage`/`DiskStorage` direct-construction precedent from batches 1–2.
- [ ] [ADD MORE AS DECIDED]

## 6. Blockers & Open Questions

- None currently open.

## 7. Last Session Summary

- **Date:** 2026-08-04 (batch 3)
- **What was done:**
  - Regenerated the coverage baseline (`./Scripts/coverage.sh`, full 882-test suite green) before scoping batch 3, per the plan left in the previous session's §8.
  - Cross-referenced `coverage-report.txt` against every file under `Sources/RequestDL/Tasks/Sources/Modifiers/` and found 2 files genuinely below 85% line coverage — `Progress/Extensions/AsyncBytes+Collect.swift` (83.02%) and `Progress/Extensions/AsyncResponse+Collect.swift` (73.44%, the lowest in the whole directory) — plus one borderline file, `Flat Map Error/Modifiers.FlatMapError.swift` (86.96% line / 70% region), worth a quick look since the region number was unusually low for something already passing the line-coverage floor.
  - Fixed all three to 100% line/region/function coverage. Full suite: 888 tests passing (up from 882). See §3 batch-3 entry for the specific gaps and the fixes; see §5 for the two new general decisions this session established (the `@autoclosure` metadata-logging gap, and direct-constructing `Internals.AsyncResponse`/`AsyncBytes` via `@testable import` for a fallback branch unreachable through any real network round-trip).
  - Incidentally, `On Status Code/Modifiers.OnStatusCode.swift` also moved from 91.67%/97.62% to 100%/100% between the pre- and post-batch coverage runs, with no test targeting it directly — likely a side effect of the new tests exercising more of the shared `RequestTask`/`AsyncResponse` plumbing. Not investigated further since it wasn't a target and is a coverage improvement, not a regression.
  - `Tasks/Sources/Modifiers/` is now effectively done: every file is ≥88% region / ≥93% line. Two files remain just above the 85% floor without being chased to 100% — `Key Path/Modifiers.KeyPath.swift` (93.75% region/100% line, 1 region miss) and `On Status Code/Models/StatusCode.swift` (88.89% region/96% line, 1 line miss at line 250, a `return nil` branch) — left alone per the established "only chase files below 85%" discipline from batches 1–2, not investigated in detail.
- **What was NOT finished:** Priority 3 (`Tasks/Sources/Interceptors/`), priority 4 (`Request/`) still not started — batch 4 should move there per §2/§8. `Internals/` (priority 5) stays indirect-only.
- **Coverage delta (line %, before → after):**
  | File | Before | After |
  |---|---|---|
  | `Modifiers.FlatMapError.swift` | 86.96% | 100% |
  | `AsyncBytes+Collect.swift` | 83.02% | 100% |
  | `AsyncResponse+Collect.swift` | 73.44% | 100% |
- **Commands that work:**
  - `swift test` — full suite, 888 tests passing as of this session. Saw one flaky single-test failure on one run that vanished on immediate re-run with no code changes in between (consistent with this branch's known event-loop-thread-starvation flakiness, see `6af08ba` in git log) — re-run `swift test` once if you see an isolated failure before assuming a regression.
  - `swift test --filter RequestDLTests.<SuiteName>` or `.../<SuiteName>/<testName>`
  - `./Scripts/coverage.sh` — same as before, ran 3 times this session (baseline, after the three fixes, after the follow-up `FlatMapError` typed-overload fix).
  - `swift format format --in-place --recursive Tests/RequestDLTests/Tasks/Sources/Modifiers/` — no diffs beyond the new/edited files.
  - `Logger.withTesting(level:metadata:recorded:perform:)` (`Tests/RequestDLTests/Utils/TestLogHandler.swift`) — previously-unused test helper, now proven out; reach for it whenever a test needs to assert on what gets logged (sets `RequestEnvironmentValues.current.logger` via the task-local for the duration of the `perform` closure, so call `.result()` inside it).

### Superseded — 2026-08-03 (batch 2, continuation of the same-day batch 1 session)
- **What was done:**
  - Worked through all 10 batch-2 target files from §8 (previous session's plan) plus a further sweep of every other `Properties/Sources/` file still below 85%, bringing the module to 27/30 files at or near 100% (3 legitimately unreachable without source changes — see below).
  - **Found and fixed a real bug** in `DiskStorage.updateCached` (`Sources/RequestDL/Properties/Sources/Cache/Data Cache/Models/DiskStorage.swift`): cache-entry directory names were derived from `Int(date.timeIntervalSinceReferenceDate)` — whole-second precision. Two records for the same key created within the same second (e.g. an initial cache write immediately followed by a revalidation, which is exactly what `Internals.CacheControl`'s 304 revalidation path does) collide on the same directory name. `moveItem` then throws on the collision, the catch block removes the (colliding) new directory, and the unconditional cleanup that follows removes the old one too — **the cache entry is silently lost, both old and new**. Reproduced directly (test failed without a delay between writes, passed with a 1.1s `Task.sleep` inserted as a diagnostic — that sleep was removed once the real fix landed). Fix: switched the directory-naming timestamp from second to nanosecond precision (`Sources/RequestDL/Properties/Sources/Cache/Data Cache/Models/DiskStorage.swift:72-79,99-104`). User approved fixing it before it was touched (via `AskUserQuestion`, choosing "fix it now" over "sleep workaround" or "skip the test").
  - **Corrected a batch-1 mistake**: `_PropertyModifier_Content.swift` and `ReadingMode.swift` were wrongly written off in batch 1 as the same "unreachable `Never.body`" dead code as `Never+Property.swift`. They are not — see the new rule in §5. Both, plus `PropertyReader.swift` (found via the same systematic grep), just needed the standard `neverBody` test every sibling `Property` type already has. All three now 100%.
  - Added/extended 16 test files (11 new, 5 extended) totaling roughly 70 new `@Test` functions/assertions across all batch-2 + sweep targets, listed in §4.
  - Investigated and deliberately skipped 3 files: `CachePolicyProperty.swift`, `CacheStrategyProperty.swift` (both `private struct`s — `body: Never` uncallable from `Tests/` without loosening access, which the project rule forbids), and `DataCache.Buffer.swift` (`readableBytes` is dead unused internal API; `writeBuffer`'s nil-guard only fires on an internal invariant violation).
  - Full suite: 882 tests passing (up from 855 baseline reported end of batch 1 — some of that delta is batch-2 tests, some is tests that existed on disk but hadn't been counted in that stale number).
- **What was NOT finished:** `Tasks/`, `Request/`, `Internals/` modules (priorities 2–5) still not started — batch 3 should move there per §2/§8.
- **Coverage delta (line %, before → after; "before" is the fresh-at-start-of-batch-2 snapshot, not the stale pre-batch-1 numbers in the old §8):**
  | File | Before | After |
  |---|---|---|
  | `SystemProxy.swift` | 0% | 100% |
  | `FlexibleURLError.swift` | 0% | 100% |
  | `FlexibleURLNode.swift` | 91.75% | 95.88% (remaining 4 lines: `URLComponents` init failing after `URL(string:)` already succeeded — investigated, could not construct a real string that triggers it; Foundation's `URLComponents` auto-percent-encodes almost everything `URL(string:)` would already have rejected) |
  | `RenegotiationSupport.swift` | 80% | 100% |
  | `PropertyNamespace.swift` | 80% | 100% |
  | `_Container.swift` | 81.25% | 100% |
  | `AcceptCharsetHeader.swift` | 82.35% | 100% |
  | `DefaultTrustRoots.swift` | 82.35% | 100% |
  | `Certificate.swift` | 84.21% | 88.16% (remaining lines: a `preconditionFailure()` crash path when a bundle resource can't be resolved — not testable without crashing the test process) |
  | `MemoryStorage.swift` | 80.20% | 97.03% (remaining: `fatalError()`/defensive branches that require breaking the `identifiers`/`records` sync invariant) |
  | `DiskStorage.swift` | 81.01% | 93.23% (remaining: disk I/O failure branches — open/read/write errors — not reachable without fault injection) |
  | `_PropertyModifier_Content.swift` | 70% | 100% (batch-1 miscategorization, see above) |
  | `ReadingMode.swift` | 84.21% | 100% (batch-1 miscategorization, see above) |
  | `PropertyReader.swift` | ~83% | 100% |
  | `Seed.swift` | 75% | 100% |
  | `EncodablePayloadFactory.swift` | 80.39% | 100% |
  | `ContentType.swift` | 83.72% | 100% |
- **Commands that work:**
  - `swift test` — full suite, 882 tests passing as of this session
  - `swift test --filter RequestDLTests.<SuiteName>` or `.../<SuiteName>/<testName>`
  - `./Scripts/coverage.sh` — regenerates `coverage-report.txt` + `coverage-lines.txt` at repo root (takes a few minutes; runs the full suite with coverage instrumentation). Ran 3 times this session; safe to re-run whenever the on-disk numbers might be stale relative to uncommitted edits — the `-instr-profile`/binary pairing errors out loudly ("profile data may be out of date") if you instead try to reuse a stale `.build/.../codecov/default.profdata` against a rebuilt test binary.
  - `swift format format --in-place <paths...>` — used on every touched file this session, no diffs beyond what was expected
  - Python one-liner pattern for sweeping `coverage-report.txt` for `Properties/Sources/` files below a threshold (regex-splits the fixed-width columns since paths can contain spaces): see the coordinator's tool history from this session if reconstructing it, or just recompute from scratch — nothing here is worth persisting verbatim.

## 8. Next Steps

1. [ ] `coverage-report.txt`/`coverage-lines.txt` at repo root reflect the end-of-batch-3 state (regenerated after all fixes landed, full 888-test suite green). Re-run `./Scripts/coverage.sh` at the start of batch 4 only if uncommitted changes have landed since, or just to be safe.
2. [ ] `Properties/Sources/` and `Tasks/Sources/Modifiers/` are both effectively done (see §2). Don't re-investigate their documented skips/left-alone files without a new angle.
3. [ ] **Batch 4: move to priority 3, `Tasks/Sources/Interceptors/`** (per §2). Side-effect observers (`RequestTaskInterceptor.output(_ result: Result<Element, Error>)`) — test via `.result()` + stubs, same convention as Modifiers. Then priority 4 (`Request/`: `RequestConfiguration`, `RequestBody`). `Internals/` (priority 5) stays indirect-only per the existing rule.
4. [ ] Before writing tests for an `Interceptors/` file, check `coverage-report.txt` for its current line/region coverage and cross-reference `coverage-lines.txt` for exact uncovered lines — same workflow as batches 1–3.
5. [ ] Apply the corrected `Never.body`/constructibility rule from §5 up front: for every `Property`/`RequestTaskModifier`/`RequestTaskInterceptor` type with a `body: Never` (or equivalent placeholder) getter, check whether the type is constructible before assuming it's dead code.
6. [ ] New this session, apply going forward: if a `log(...)` call's metadata-building lines show 0 executions despite the function itself executing, check for `@autoclosure` params before assuming dead code — see §5. And for defensive/fallback branches unreachable through real integration flows, check whether `@testable import` direct construction of the internal type can reach it (per the new §5 entries) before writing it off.
7. [ ] After batch 4: `swift test`, `swift format format --in-place --recursive Tests`, re-run `./Scripts/coverage.sh`, diff against this session's numbers, update this file again.
8. [ ] Do not commit/push new tests without going through `/commit-push` and explicit user confirmation.
9. [ ] `coverage-report.txt`, `coverage-lines.txt`, and (new as of this session) `job-logs.txt` are still untracked and not in `.gitignore` as of batch 3 — still unresolved after being flagged at the end of batch 2 too. Flag to the user again at the next commit.
8. [ ] `coverage-report.txt` and `coverage-lines.txt` are still untracked and not in `.gitignore` as of this session — still unresolved, flag to the user again at the next commit.
