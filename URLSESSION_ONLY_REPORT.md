# URLSession-only build: isolation status

Tracks a multi-session effort to make `RequestDLInternals` (and the parts of `RequestDL` that
touch it) compile without any of the NIO family — `NIOCore`, `NIOSSL`, `NIOHTTP1`,
`AsyncHTTPClient`, etc. — so that a future SPM trait can offer a Darwin/`.urlSession`-only build
that never links NIO at all: no dependency to fetch, no code to compile, smaller binary.

**No such trait exists in `Package.swift` yet** — that's still future work — **but the compile
target itself is done and verified for real.** Every change described here is behind
`#if canImport(NIOCore)` (never `#if canImport(Darwin)` — see "The one rule" below), which
evaluates `true` unconditionally today since NIOCore is always a dependency of this package, so
none of it changes today's actual build. What changed this session: rather than resting on "this
is provably safe because the `#else` branch is unreachable," every `#if canImport(NIOCore)` in
both `RequestDLInternals` and the touched parts of `RequestDL` was temporarily forced to its
`false` branch (a scripted, reverted-before-commit sed pass, not a permanent change) and the whole
package — `swift build`, the full `RequestDLInternals`/`RequestDL` targets — was compiled for
real against that forced state. It built clean. That is the actual claim this file makes now:
today, right now, `RequestDLInternals` and `RequestDL`'s NIO-touching call sites all have a
genuine, compiling, non-NIO path — not just a documented intention to have one. (Test *targets*
were not forced through the same exercise — see "What 'done' does and doesn't mean" below.)

Finishing the SPM trait itself, and re-running this same forced-build check against it once it
exists (a real, not scripted, `!canImport(NIOCore)` build), is what's left.

Delete this file (and update the `urlsession-only-trait-isolation` memory that points to it) once
the trait exists and this whole effort is done — same lifecycle as `URLSESSION_TASK.md`/
`URLSESSION_REPORT.md`, the analogous tracking docs for the (now-complete, separate) migration
that originally wired up the `.urlSession` executor itself.

## The one rule

**Gate on `#if canImport(NIOCore)`, never `#if canImport(Darwin)`.** They look similar but answer
different questions. `canImport(Darwin)` means "are we on an Apple OS" — used throughout this
codebase to gate `.urlSession`/Network.framework-specific code that has nothing to do with this
effort. `canImport(NIOCore)` means "is the NIO family available in this build" — the actual trait
boundary. A Darwin/URLSession-only trait-off build is still Darwin, so `canImport(Darwin)` stays
true there; only `canImport(NIOCore)` goes false. Mixing the two up gates the wrong thing.

Corollary worth stating explicitly: **a NIOCore-off build only makes sense combined with
Darwin.** Linux has no executor but `.nio` in this codebase, so "no NIOCore, not Darwin either"
is not a configuration anyone wants — don't add defensive handling for it.

## How to check progress

```bash
grep -rl '^import NIO\|^import NIOSSL\|^import NIOHTTP1\|^import NIOPosix\|^import NIOTransportServices\|^import NIOEmbedded\|^import NIOConcurrencyHelpers\|^import NIOFoundationEssentialsCompat\|^import _NIOFileSystem\|^import AsyncHTTPClient\|^import NIOHTTPCompression\|^import NIOCore' Sources/RequestDLInternals | sort
```

This lists every file that mentions the NIO family *at all*, gated or not — it does **not**
distinguish "fully NIO-only forever, correctly so" from "still blocking a real NIO-off build."
Both the very first audit and the current one land around 55–60 files; the count staying flat is
expected and not a useful progress signal on its own — several files were *added* (the new
portable mirror types below, which are gated) while others were *fully removed* from the list
(`BodySequence`, `CompressingByteSequence`, `ManualDecompressionDispatch`, `RedirectRequest`,
`DecompressionAlgorithm`, `URLSessionClient.Redirect`, `ServerTrustPolicy`, the main
`ClientManager` file, `URLSessionUploadFile`). What actually matters is reading each remaining
hit and classifying it into one of the four buckets below.

After finishing any of the "Open" items, always run the full suite before considering it done:

```bash
swift build
swift test
```

Expect **1220 tests / 168 suites** (`RequestDLTests`) + **560 tests / 84 suites**
(`RequestDLInternalsTests`), both passing, with exactly **3 + 4 known issues** — all pre-existing
Keychain flakiness in this sandboxed SwiftPM test harness (`SecItemCopyMatching` failing with
`OSStatus -25300`), unrelated to this effort. A different known-issue count, or fewer total
tests, means something broke.

## The four buckets every NIO-touching file falls into

1. **Fully removed** — the file used to import NIO unconditionally and no longer imports it at
   all, in any form. Nothing left to do.
2. **Fully gated** — every NIO reference in the file sits behind `#if canImport(NIOCore)`; the
   file compiles today (NIOCore present) and would compile equally well with it absent (all NIO
   code simply isn't there). Nothing left to do.
3. **Partially gated** — some of the file (usually stored properties / public API surface) is
   portable, but part of it (usually a `build()`/conversion method producing a real NIO type) is
   still unconditional. This is the state most "done" items below are actually in — it's a
   deliberate, correct intermediate state (see "Why partial gating is fine" below), not
   unfinished work. `Internals.SecureConnection.swift`'s own `build()`/`Output` — once *the*
   named blocker for the whole target — is now itself gated too; see the Done table.
4. **Untouched** — still unconditionally imports NIO throughout, never looked at. See the Open
   section for what's left.

### Why partial gating is fine

A type like `Internals.ConnectionPool` or `Internals.Timeout` stores portable fields (`Int64`
nanoseconds, plain enums) and has one `#if canImport(NIOCore)`-gated `build()` method that
produces the real `HTTPClient.Configuration.X` value. The **file** still imports `AsyncHTTPClient`
unconditionally at the top for that one method's return type — that's correct, not a gap: the
`build()` method's whole purpose is feeding a NIO-only executor, so of course it needs NIO
present when called. What matters is that the *storage* (what a shared, executor-agnostic type
like `Internals.Session.Configuration` holds) no longer forces NIO on code that never resolves to
`.nio`. The pattern is: **push the unconditional NIO dependency down to the narrowest possible
conversion method, keep everything above that method portable.**

## Established patterns (read before writing new code here)

These are the concrete techniques this effort settled on, in the order they tend to come up:

### 1. Portable mirror types

When a shared struct (used by both executors) stores a NIO/NIOSSL-typed field, give it a
`package`-visibility `Internals.X` type instead, matching the NIO type's cases/`RawRepresentable`
shape exactly, with a `#if canImport(NIOCore)`-gated `build() -> NIOSSL.X`/`NIOCore.X` method.
Examples already in the tree: `Internals.Bytes` (`Sources/RequestDLInternals/Sources/Buffers/Data/Models/Internals.Bytes.swift`),
`Internals.HTTPHeaders`, `Internals.ConnectionPool`, `Internals.CertificateVerification`,
`Internals.RenegotiationSupport`, `Internals.TLSVersion`, `Internals.SignatureAlgorithm`,
`Internals.TLSCipher` (all in `Sources/RequestDLInternals/Sources/Secure Connection/Secure Connection/Models/`).

**If a raw value/case set is copied from a NIOSSL type (cipher suite IDs, signature algorithm
IDs, TLS version enums), verify it against the actual checked-out source before writing it down.**
Don't trust memory for these, even when confident — a wrong raw value is a silent,
security-relevant bug (wrong cipher/algorithm gets negotiated) that no type checker catches. The
resolved package sources are locally available for exactly this:
```bash
find /Users/brenno/.cache/swifterpm/sources/swift-nio-ssl -o -path "*/.build/checkouts/swift-nio-ssl*"
```
(This session found the real `.build/checkouts/swift-nio-ssl/Sources/NIOSSL/TLSConfiguration.swift`
and diffed every `TLSCipher`/`SignatureAlgorithm` raw value against it before committing to them —
worth repeating for any type this pattern gets applied to next.)

### 2. RequestDL's own public mirror types often already exist — reuse their shape, not their code

`RequestDL.CertificateVerification`/`SignatureAlgorithm`/`TLSCipher`/`TLSVersion`/
`RenegotiationSupport` already existed as public, NIOSSL-typed-`.build()` wrappers before this
effort. `RequestDLInternals` can't import `RequestDL` (wrong direction), so the portable mirror
had to be re-declared inside `RequestDLInternals`, matching the public type's case names/raw
values exactly. The public type's own `.build()` return type then changes from the raw NIOSSL
type to the new `Internals.X` type (its only callers were the `RequestDL`-layer property wrapper
assigning straight into `Internals.SecureConnection` — verify that's still true for any new type
before changing a `.build()` return type, a stray direct caller elsewhere would break).

### 3. The boundary-conversion type: `Internals.Bytes`

For the one place two executors need a literal shared byte currency (`Internals.BodySequence`
chunks, the compression stream protocols), a portable mirror alone doesn't help because the value
might already exist natively as either representation and forcing one loses a free
zero-copy opportunity. `Internals.Bytes` is a struct backed by a private
`enum { case data(Data), #if canImport(NIOCore) case byteBuffer(NIOCore.ByteBuffer) #endif }`,
lazily materializing whichever representation is asked for and caching the result. Full writeup
in that file's own doc comment. Only reach for this pattern at a genuine two-executor boundary —
everywhere else a plain portable mirror (pattern 1) is simpler and correct.

**Zero-copy conversion trick used inside it**: `NIOCore.ByteBuffer` → `Data` can avoid a `memcpy`
via `NIOFoundationEssentialsCompat`'s `getData(at:length:byteTransferStrategy: .noCopy)` — it
wraps the buffer's existing storage in `Data(bytesNoCopy:count:deallocator:)`, keeping a
reference alive instead of copying. The reverse direction (`Data` → `ByteBuffer`) has **no**
equivalent — `ByteBuffer` always copies on that side, since it needs its own pooled storage.
`.automatic` (the default strategy) copies below 256KB and no-copies above — that threshold is
NIO's own, don't second-guess it.

### 4. Narrow the public API surface, don't throw at runtime, when the type system can express it

Preferred over a runtime error whenever a case set can just shrink: `Internals.Executor` only has
`.urlSession` without NIOCore (`.nio`/`.nioTransportServices` cases are gated); `Session.Executor`
(public) mirrors that; `SessionProvider.group(with:)` isn't a protocol requirement without NIOCore;
`Session.init(_ customLoopGroup: NIOCore.EventLoopGroup)` doesn't exist; 12 `SecureConnection`
builder methods (`.renegotiationSupport(_:)`, `.keyLogger(_:)`, 4 of 5 `.version(...)` overloads,
etc. — see `Sources/RequestDL/Properties/Sources/Secure Connection/Secure Connection/SecureConnection.swift`)
don't exist; `SSLKeyLogger`/`SSLPSKIdentityResolver` protocols and `PSKIdentity` don't exist. A
caller who tries to configure something meaningless without NIO gets a compile error at their own
call site, not a request-time `ExecutorRequirementError` — better still, not a **silent no-op**,
which is what would otherwise happen: without NIOCore, `resolveExecutor()` unconditionally
returns `.urlSession`, so a NIO-only setting would just be quietly ignored rather than throwing.

**Runtime throw is the fallback only when the type system can't express the restriction** — the
one example so far is `Compression`: `GzipAlgorithm`/`DeflateAlgorithm`'s `Compressor
.callAsFunction()` throws `CompressionUnavailableError` under a final `#else`, once NIO *and*
`zlib` are both unavailable, instead of the type just not existing, because the *protocol
conformance itself* (`Compressor`) has to exist either way for the type to keep conforming. Both
algorithms now have a portable, `zlib`-backed implementation in between those two extremes
(`PortableGzipCompressorStream`/`PortableDeflateCompressorStream`, done — see the former Open
Item 2, now closed), so this error is the fallback of a fallback, not the everyday NIO-off
behavior it used to be.

## Done

| # | Item | State |
|---|---|---|
| — | `Internals.Bytes` (opaque `Data`/`ByteBuffer` currency) | Fully gated |
| — | `Internals.HTTPHeaders` (replaces `NIOHTTP1.HTTPHeaders` in `Proxy`/`RedirectRequest`) | Fully gated |
| — | `Internals.BodySequence`/`CompressingByteSequence` | Fully removed |
| — | `CompressorStream`/`DecompressorStream` protocols → `Data`-based | `DecompressionAlgorithm.swift` fully removed; concrete NIO codec (`Compression+Encode.swift`) stays NIO-only by design, not a gap — the portable compression side is covered separately below |
| — | `SessionProvider` (`group(with:)` conditional requirement) | Fully gated |
| — | `RequestBody.next() -> Data?` (was `NIOCore.ByteBuffer?`) | **Breaking public API change**, already shipped in this branch. `StreamWriterSequence`/`URLSessionUploadFile`/`URLSessionClient` all updated to match. |
| — | `Internals.Executor` (only `.urlSession` without NIOCore) + `resolveExecutor()`/`requireExecutor(_:)` + `Internals.ClientManager.Client` + `Session.Executor` (public) + `RawTask.resolveClient`'s dispatch switch | Fully gated |
| — | `Internals.ClientManager` split into `Internals.ClientManager.swift` (portable: table/lock/lifetime bookkeeping, no NIO import at all now) + `Internals.ClientManager+NIO.swift` (the `.nio`/`.nioTransportServices` half, whole file gated) | Fully gated |
| — | `Internals.Session.Configuration.connectionPool` → `Internals.ConnectionPool` | Partially gated (storage portable, `.build()` NIO-only, as expected) |
| — | `Internals.Proxy` (`Authorization.build()`, struct `build()`) | Partially gated |
| — | `Internals.SecureConnection`'s 8 TLS knob fields (`certificateVerification`, `signing`/`verifySignatureAlgorithms`, `renegotiationSupport`, `min`/`maximumTLSVersion`, `cipherSuiteValues`, `shutdownTimeout`) → portable `Internals.*` mirror types | Partially gated (storage portable, `build()` NIO-only, as expected) |
| — | `Internals.ServerTrustPolicy` (own `certificateVerification` copy) | Fully removed (`import NIOSSL` gone entirely) |
| — | `SSLKeyLogger`/`SSLPSKIdentityResolver` protocols (public + internal) + `PSKIdentity` Property + `Internals.SecureConnection.keyLogger`/`pskHint`/`pskIdentityResolver` fields + the 12 NIO-exclusive `SecureConnection` builder methods | Fully gated |
| — | `DeflateAlgorithm`/`GzipAlgorithm`'s `Compressor` (outbound request-body compression) → `PortableDeflateCompressorStream`/`PortableGzipCompressorStream`, both gated on `!canImport(NIOCore) && canImport(zlib)`, falling back to `CompressionUnavailableError` only if even `zlib` is missing | Fully gated (both algorithms) |
| — | `Internals.fileSystem`/`FileSystemManager.run` → `Internals.PortableFileSystem` (`FileManager`/`FileHandle`, offloaded via `DispatchQueue.global()`), consumed unchanged by `FileStreamBuffer`/`FileBufferURL`/`URL+Extensions.swift`/`DiskStorage.swift` | Fully gated — see "Disk I/O" writeup below |
| — | `Internals.SecureConnection.build()`/`Output`/`makeTLSConfigurationByContext(_:)`/`makeLocalIdentityForNetworkFramework()` | Fully gated — narrowed away entirely (no portable counterpart needed; see "SecureConnection itself" writeup below) |
| — | `Internals.Certificate`/`CertificateChain`/`TrustRoots`/`AdditionalTrustRoots` → portable `resolvedDERBytes()` (`SwiftASN1`-backed), replacing the NIOSSL round-trip in `RawBytesIdentityBuilder`/`ServerTrustPolicy`/`ClientIdentityDescriptor` | Fully gated — see "Certificate DER extraction" writeup below |
| — | `Internals.DarwinTrustEvaluation.chainSPKIDERBytes(of:)` → `X509`-based SPKI extraction, replacing `NIOSSLCertificate.spkiDERBytes()` (now-dead `NIOSSLCertificate+SPKI.swift` deleted) | Fully gated |
| — | `Internals.PrivateKey.password`/`PrivateKeySource` → `Internals.SecureBytes` (portable mirror of `NIOSSLSecureBytes`) + public `RequestDL.SecureBytes`, new additive `PrivateKey` initializer overloads | Fully gated (existing `NIOSSLSecureBytes`-taking overloads untouched, still available when NIOCore is present) |
| — | `PropertyMockedTask` (the `.mockedTask` feature) → rewritten on `RequestBody`'s own `AsyncSequence` conformance instead of `EventLoopGroup`/`HTTPClient.Body` | Fully portable now for both executors, not just gated — see "Mock task portability" writeup below |
| — | `Internals.Session`/`Client`/`UnsafeTask`/`ClientResponseReceiver`/`EventLoopGroupManager`/`MultiThreadedEventLoopGroup`/`TSEventLoopGroup`/`NIORedirectStrategyAdapter`/`NIOTrustEvaluator`(`+Darwin`)/`StreamWriterSequence`, `Internals.Session.Configuration`'s `build()`/`Output`, `HTTPVersion`/`RedirectConfiguration`/`Timeout`'s `build()`, `RequestBody`/`RequestConfiguration`'s `build(eventLoop:)`, `Internals.Client+RequestExecutingClient.swift` | Fully or partially gated — the "everything else" pass; see "The rest of the core" writeup below |
| — | `Internals.AsyncBytes`/`AsyncResponse`/`SessionTask`/`DownloadBuffer` | `import NIOCore` was dead in all four — deleted, no gate needed |
| — | `Internals.Storage.lifetime` → `Int64` nanoseconds (was `NIOCore.TimeAmount`) | Fully portable, matches the `Internals.Timeout`/`ConnectionPool` convention |
| — | `Internals.URLSessionClient.swift`'s one real `ByteBuffer` construction (`Internals.ByteURL(ByteBuffer(bytes: data))`) → `Internals.ByteURL()` + `.replace(with:)` | Fully portable; `import NIOCore` was otherwise unused in this file and is now gone |
| — | `Internals.TLSVersion.urlSessionProtocolVersion` moved onto the portable mirror directly (was an extension on `NIOSSL.TLSVersion`) | `.urlSession`'s own config-building path no longer needs NIOSSL for this |

### Certificate DER extraction (closed out this session)

`RawBytesIdentityBuilder.certificateDERs(from:)` and `ServerTrustPolicy.resolve(from:)` (the
`.urlSession` mTLS/pinning path — reachable and exercised today, not hypothetical) both used to
round-trip through NIOSSL just to get DER bytes back out: `CertificateChain.build()`/
`TrustRoots.resolvedCertificates()` (NIOSSL parsing) followed immediately by `.toDERBytes()`
(NIOSSL serializing back out). That meant two Darwin-only, `.urlSession`-reachable files secretly
depended on NIOSSL despite never importing it directly (the same cross-module-visibility gap
`Internals.ServerTrustPolicy.swift`'s own "`import NIOSSL` gone entirely" Done row already ran
into once) — `Internals.ClientIdentityDescriptor.swift` (`BackgroundDownloadTask`'s client-cert
rebuild) had the identical pattern, found only by force-compiling the whole package and watching
it fail there too.

Fixed by giving `Internals.Certificate` a portable `resolvedDERBytes() -> [Data]`, built on
`SwiftASN1`'s `PEMDocument.parseMultiple(pemString:)` rather than a hand-rolled PEM splitter.
`SwiftASN1`/`X509` are already portable package dependencies — confirmed by reading
`swift-certificates`'s own `Package.swift` (`X509` depends only on `SwiftASN1`, `Crypto`,
`_CryptoExtras`, none of which touch NIOCore), not assumed. `CertificateChain`/`TrustRoots`/
`AdditionalTrustRoots` each grew their own `resolvedDERBytes()` built on the same primitive.

One real, non-obvious behavioral asymmetry, confirmed by test rather than assumed: `build()`'s
`.bytes` case constructs a single `NIOSSLCertificate(bytes:format:)` (silently keeps only the
*first* certificate in a multi-certificate PEM blob) while its `.file` case calls
`NIOSSLCertificate.fromPEMFile`/`.fromPEMBytes` (reads every certificate). `resolvedDERBytes()`
deliberately reproduces this asymmetry rather than "fixing" it silently while porting — see
`Internals.Certificate.resolvedDERBytes()`'s own doc comment and
`InternalsCertificateTests.resolvedDERBytes_whenPEMBundleBytesHasMultipleCertificates_matchesBuildsSingleCertificateBehavior()`.
Verified byte-for-byte against `NIOSSLCertificate`'s own DER output across `.bytes`/`.file`,
`.pem`/`.der`, single- and multi-certificate bundles, and malformed-input error paths.

### SecureConnection itself (closed out this session)

Turned out **not** to need a portable counterpart at all. `Internals.SecureConnection.build()`/
`Output`/`makeTLSConfigurationByContext(_:)`/`makeLocalIdentityForNetworkFramework()` have exactly
one caller in the whole codebase — `Internals.Session.Configuration.build()`, which itself exists
only to construct an `HTTPClient.Configuration` (a NIOCore/AsyncHTTPClient-only type, consumed
only by `Internals.ClientManager+NIO.swift`, the `.nio`/`.nioTransportServices` client builder).
`.urlSession` never touches any of this: it reads `certificateChain`/`privateKey`/`trustRoots`/
etc. straight off `Internals.SecureConnection`'s own portable fields, through
`ServerTrustPolicy`/`URLSessionIdentityPolicy`/`RawBytesIdentityBuilder` instead. So the whole
`build()`/`Output` surface (and `Internals.Session.Configuration.build()`/`Output` one layer up)
is narrowed away entirely under `#if canImport(NIOCore)` — the same "narrow the public API
surface" pattern already used for `Internals.Executor`'s `.nio` cases, not a new technique.

### Mock task portability (closed out this session)

`PropertyMockedTask` (`.mockedTask`) used to construct `Internals.Client` (the NIO-only client)
and drive the request body through `EventLoopGroup`/`HTTPClient.Body.stream` unconditionally,
regardless of which executor the surrounding `Session` actually resolved to — a real capability
gap for a URLSession-only build, not a mechanical gate: the whole feature would have silently
stopped existing. Fixed properly, not gated: `mockBodyResponse` now drives `RequestBody` through
its own `AsyncSequence` conformance (`for try await chunk in body`), appending each chunk to
`Internals.DownloadBuffer` via `Internals.ByteURL()` + `.replace(with:)` — no `EventLoopGroup`
needed for either executor, since `RequestBody` was already portable. The client-resolution half
now goes through `resolvedClient()` (the executor-aware entry point `RawTask.resolveClient(_:)`
already uses) instead of `Internals.ClientManager.shared.client(...)` (NIO-only). Net effect: the
mock feature works identically for both executors today, and needs no further change once the
trait exists.

### The rest of the core (closed out this session)

Force-compiling the whole package surfaced a long tail of files that were either never gated
despite the report already classifying them as bucket A (`Internals.NIOTrustEvaluator.swift`/
`+Darwin.swift` — the report said "legitimately NIO-only forever, no work needed" but nobody had
actually wrapped them), or genuinely shared types nobody had looked at yet
(`Internals.Session`/`Client`/`ClientResponseReceiver`/`UnsafeTask`/`EventLoopGroupManager`/
`MultiThreadedEventLoopGroup`/`TSEventLoopGroup`/`NIORedirectStrategyAdapter`/
`StreamWriterSequence`, `Internals.Session.Configuration`'s own `build()`/`Output`,
`HTTPVersion`/`RedirectConfiguration`/`Timeout`'s `build()` methods, `RequestBody`/
`RequestConfiguration`'s `build(eventLoop:)`, `Internals.Client+RequestExecutingClient.swift`).
Each was checked for real usage (grep for non-doc-comment references, not assumed from the file
name) before gating, to avoid accidentally walling off something `Internals.URLSessionClient.swift`
still needed — `Internals.AsyncBytes`/`AsyncResponse`/`SessionTask`/`Internals.DownloadBuffer`
turned out to already be shared and portable, with a merely *dead* `import NIOCore` each (deleted,
not gated), confirmed by successfully building with the import removed before committing to that
conclusion.

### Compression codec (closed out this session)

`Internals.NIOHTTPCompressorStream` (`Internals.Compression+Encode.swift`) is still the only
`CompressorStream` implementation NIO itself provides, built on `NIOHTTPRequestCompressor`. For
the portable side, a Darwin-only alternative using Apple's `Compression` framework was researched
by reading how **Alamofire** solves the exact same problem
(`Source/Features/RequestCompression.swift`'s `DeflateRequestCompressor`, fetched straight from
`Alamofire/Alamofire` on GitHub rather than trusted from memory), then extended from deflate to
gzip:

- Neither implements response *decompression* — handled transparently by URLSession/Foundation
  itself before the response reaches app code, same free lunch this codebase's own `Decompressor`
  doc comment already describes for `.urlSession`.
- For outbound compression, both take the **raw deflate** bytes from
  `NSData.compressed(using: .zlib)` (Apple's `Compression` framework via Foundation) and wrap
  them with a format-specific header/trailer instead of hand-rolling deflate itself: zlib's is a
  fixed 2-byte header (`0x78, 0x5E`) plus a big-endian Adler-32 trailer (`zlib`'s own `adler32()`);
  gzip's is a 10-byte header (magic `0x1F 0x8B`, method, flags, zeroed mtime, unset xfl, OS
  "unknown") plus a little-endian CRC-32 (`zlib`'s `crc32()`) and a little-endian `ISIZE`
  (uncompressed size mod 2^32).

Two **non-obvious things confirmed by testing, not assumed**:

1. `NSData.compressed/decompressed(using: .zlib)` — despite the name — is backed by
   `COMPRESSION_ZLIB`, which is actually **raw DEFLATE (RFC 1951)**, not an RFC 1950 zlib stream.
   Feeding a hand-wrapped zlib stream back into `NSData.decompressed(using: .zlib)` fails for
   exactly that reason. Verified with a standalone script (round-tripped through real zlib
   `inflate()`, not `NSData`, across empty/small/large/random-binary payloads) before writing any
   package code.
2. The gzip container built the same way is genuinely valid RFC 1952 — not just theoretically, but
   confirmed by writing real `.gz` files from a standalone script and validating them with the
   system `gunzip -t` (plus a byte-for-byte content check against a random binary payload), which
   is effectively the same decoder real HTTP servers use. The "gzip needs real interop testing"
   concern the original audit raised is what this was.

**Applied**: both `DeflateAlgorithm`/`GzipAlgorithm`'s `Compressor` now have portable fallbacks,
[`PortableDeflateCompressorStream`](Sources/RequestDL/Properties/Sources/Compression/Models/PortableDeflateCompressorStream.swift)/
[`PortableGzipCompressorStream`](Sources/RequestDL/Properties/Sources/Compression/Models/PortableGzipCompressorStream.swift),
built on this technique. Each `callAsFunction() -> CompressorStream` is a three-way
`#if canImport(NIOCore) / #elseif canImport(zlib) / #else`: the checksum trailer is a genuine,
narrower dependency on the `zlib` C library, separate from the NIOCore/Darwin question this whole
effort otherwise turns on, so it gets its own condition rather than being folded into "NIO absent
means Darwin" — if `zlib` somehow isn't importable either, both still degrade to
`CompressionUnavailableError` instead of a hard compile error. One deliberate simplification
versus `NIOHTTPCompressorStreamBridge` in both: they buffer the whole body and compress once in
`finish()` rather than streaming incrementally, since `Compression`'s buffer-based API has no
incremental entry point the way `NIOHTTPRequestCompressor` does. `CompressorStream`'s own doc
comment explicitly allows returning `[]` until `finish()`, so this is a correct implementation,
just not memory-bounded for very large bodies the way the NIO path is
(`applyCompression_whenBodyIsLarge_compressesInBoundedMemoryAcrossManyChunks` in
`RequestConfigurationCompressionTests.swift` covers that property today, but only exercises the
NIO path, since `#if !canImport(NIOCore)` still never evaluates `true` in this build). Revisit
with `compression_stream`'s true incremental C API if bounded memory ever becomes a real
constraint for a shipped URLSession-only build.

Both verified by temporarily forcing each branch to compile (`#if true`/`#if false` swapped in
locally, never committed) against the real `CompressorStream` protocol, followed by the full test
suite, since `swift build`/`swift test` can't reach any of this normally — none of it is exercised
until the trait exists, same as everything else in this file.

### Disk I/O (closed out this session)

`Internals.FileBufferURL.swift`/`Internals.FileStreamBuffer.swift`/`Internals.FileSystemManager
.swift` were 100% `NIOFileSystem`/`NIOPosix`/`NIOThreadPool` at the start of this session. Two
questions had to be answered before writing any portable replacement, per the original audit's
own instruction not to reintroduce whatever `NIOFileSystem` was adopted to fix:

1. **Why `NIOFileSystem` over `SystemPackage.FileDescriptor`?** Answered by
   `Internals.FileStreamBuffer.swift`'s own doc comment, corroborated by nearby git history
   (`7c4eab9c` "Fix cancellation handling and add lock watchdogs...", `7ed46171` "Relax
   AsyncLock.Watchdog thresholds..."): a prior `FileDescriptor`-based revision ran the blocking
   syscall in place on whichever Swift Concurrency cooperative thread called in, and under
   `swift-testing`'s parallel execution enough concurrent callers saturated that fixed-size pool
   that a critical section merely waiting for a worker thread looked identical to one genuinely
   stuck to `AsyncLock.Watchdog` (wall time, not CPU time). `NIOFileSystem` fixed this by running
   the syscall on its own dedicated `NIOThreadPool` instead.
2. **Is that benefit unique to `NIOFileSystem`?** No — it is "don't block the cooperative pool
   with a syscall," which `DispatchQueue.global()` (GCD's own elastic worker pool, entirely
   outside Swift Concurrency's cooperative pool already) solves equally well with no NIO at all.
   The actual offset/lock bookkeeping around every read/write was already this package's own
   (`AsyncLock` + `_offset` in `FileStreamBuffer`), not delegated to `NIOFileSystem`'s API surface
   — so swapping the backend couldn't regress that property either way.

The real surface turned out wider than those three files: `DiskStorage.swift` and
`Extensions/URL+Extensions.swift` also call `Internals.fileSystem.*` directly (`info`,
`createDirectory`, `openFile`, `removeItem`, `moveItem`, `withDirectoryHandle`) — found by
grepping for every `Internals.fileSystem`/`NIOFileSystem` reference outside the three originally
flagged files, not assumed from the audit's file list.

**Applied**: [`Internals.PortableFileSystem`](Sources/RequestDLInternals/Sources/File%20System%20Manager/Internals.PortableFileSystem.swift)
mirrors the subset of `NIOFileSystem.FileSystem`'s API this package actually calls — `info`,
`createDirectory`, `openFile` (read/write), `removeItem`, `moveItem`, `withDirectoryHandle` — each
backed by `FileManager`/`FileHandle`, every blocking call routed through
`Internals.FileSystemManager.run` (also made portable: `NIOThreadPool` under NIO,
`DispatchQueue.global(qos: .utility)` without it). `Internals.fileSystem` itself resolves to
whichever backend is active (`NIOFileSystem.FileSystem` vs `PortableFileSystem.Type`), the same
"one symbol, `#if`-gated type" pattern used everywhere else in this effort.

The portable types (`WriteOptions`, `ReadLength`, `ReadLimit`, `Chunk`, `DirectoryEntry`) were
deliberately shaped to match real call-site syntax (`.newFile(replaceExisting:)`, `.bytes(_:)`,
`.unlimited`, `chunk.readableBytes`/`.readableBytesView`, `entry.name.string`) rather than
introducing a cleaner-looking but different API. The payoff: `FileStreamBuffer`'s `Handle` enum
is the *only* thing gated in that file — every method that touches it (`init`, `writeData`,
`readData`, `close`) compiles completely unchanged against either backend, so the correctness-
critical short-read/short-write retry loops and cancellation checks are never duplicated between
the two implementations. `FileBufferURL.swift` needed zero body changes at all, only its
`import NIOFileSystem` gated. `URL+Extensions.swift`/`DiskStorage.swift` needed exactly one small
`#if` each, at the single point where a `NIOFileSystem`-returned buffer's shape
(`.readableBytesView`/`NIOFoundationEssentialsCompat.getData(at:length:)`) differs from the
portable handle's plain `Data` return.

**Verified far more thoroughly than a compile check**: after force-compiling the portable branch
across all six touched files simultaneously (temporarily replacing every `#if canImport(NIOCore)`
with `#if false` and `Internals.PortableFileSystem`'s own `#if !canImport(NIOCore)` with
`#if true`, never committed), the **entire test suite was run against it**, not just typechecked —
this is a stronger verification than anything else in this file, since disk I/O is exercised by
real logic (offsets, short reads/writes, thread-pool offload), not just a synthetic script. All
1220 + 560 tests passed, including
`manyInstances_whenRunningConcurrently_shouldAllCompleteWithoutStallingTheCooperativePool` — the
regression test for the exact watchdog-false-positive problem `NIOFileSystem` was originally
adopted to fix — against the `DispatchQueue`-backed implementation. One real bug was caught this
way before it could ship dead: the first draft of `PortableFileSystem.WriteOptions.modifyFile`
was missing its `permissions` parameter entirely, a hard compile error invisible to normal
`swift build`/`swift test` since this branch never type-checks in today's build.

## What "done" does and doesn't mean

The whole-package forced-build check this session ran (see the top of this file) verified
`swift build` for both `RequestDLInternals` and `RequestDL`. It did **not** verify:

- **Test targets under the forced-off state.** `RequestDLInternalsTests`/`RequestDLTests` were
  left untouched by the forced-build pass — they're written to exercise the real, NIOCore-present
  build (comparing against `NIOSSLCertificate`/`NIOSSLPrivateKey` output, for instance), which is
  the only state they can ever actually run in until the trait exists. Attempting to force-compile
  every test file the same way the source was would mean either duplicating large parts of the
  test suite for a build that doesn't exist yet, or gating test assertions themselves — neither is
  what any earlier session in this file did either. What *was* verified: the real, NIOCore-present
  build's full test suite (`swift test`, both targets) still passes after every change — 1220
  tests / 168 suites (`RequestDLTests`) + 568 tests / 84 suites (`RequestDLInternalsTests`, up
  from 560 — new `resolvedDERBytes()` coverage), 3 + 4 known issues, matching the baseline this
  file has tracked all along.
- **Runtime behavior.** A build that type-checks without NIOCore is not the same claim as "an app
  built this way, once the trait exists, behaves correctly at runtime" — no such build has ever
  actually been produced or run. The DER-extraction/SPKI work was cross-checked against real
  output (`NIOSSLCertificate`'s own DER bytes, the system `gunzip`/`openssl`-equivalent tooling
  used elsewhere in this file) specifically because "compiles" alone wasn't going to be enough
  evidence for that piece.
- **The `RequestDL` product's own test-support/example targets**, or any downstream package that
  depends on this one — out of scope for a `swift build` of this package alone.

## Gotchas hit this session (worth knowing before continuing)

- **Xcode's live SourceKit diagnostics lag real `swift build` output constantly** across
  multi-file edits in this codebase (splitting a type across files, adding a sibling type in a
  new file). Every single time this session hit a SourceKit-reported error that `swift build`
  didn't reproduce, it was stale — treat `swift build`/`swift test`'s actual exit code and error
  list as the only source of truth; don't chase a SourceKit-only error.
- **Naming collisions across the `Internals`/`RequestDL` boundary are real.** `RequestDL` has
  several `extension Internals { struct X { ... } }` blocks (e.g. `Internals.CacheControl.swift`)
  that use an unqualified type name (`HTTPHeaders`) expecting it to resolve to `RequestDL`'s own
  public type — introducing `Internals.HTTPHeaders` silently shadowed that lookup inside those
  blocks (Swift prefers the closer, sibling-namespace match). Caught by a real compile error, not
  silently — but grep for `extension Internals` files in `RequestDL` using the bare name of any
  new `Internals.X` type before introducing it, and qualify as `RequestDL.X` where needed.
- **`Internals.Bytes.moveWriterIndex(to:)` almost shipped a wrong safety contract.** The first
  version zero-filled growth differently for the `.data` case (checked against physical
  `data.count`) vs. the `.byteBuffer` case (checked against logical `writerIndex`) — the
  `.byteBuffer` branch's original, more lenient version would have reintroduced the exact
  `NIOCore.ByteBuffer` capacity-precondition crash `Internals.ByteHandle.write(contentsOf:)`
  already works around today. Caught by writing a test that actually drove the ByteBuffer-backed
  growth path and watching it trap (`NIOCore/ByteBuffer-core.swift:1382`), not by reasoning alone
  — when in doubt about a NIO type's actual runtime behavior, write the test that exercises it
  for real before trusting a design.
- **Don't trust memory for NIOSSL raw values/case shapes.** `NIOSSL.CertificateVerification.none`
  turned out to carry an associated `NoneOptions` value (`validatePresentedCertificates: Bool`),
  not a plain case — RequestDL's own public mirror already collapses this to the simple 3-case
  version callers actually get, which is why replicating *that* shape (not NIOSSL's literal one)
  into `Internals.CertificateVerification` was correct. Confirmed by reading
  `.build/checkouts/swift-nio-ssl/Sources/NIOSSL/TLSConfiguration.swift` directly rather than
  assuming.
- **`NSData.compressed/decompressed(using: .zlib)` is not actually zlib.** Despite the name,
  `COMPRESSION_ZLIB` in Apple's `Compression` framework produces/consumes raw DEFLATE (RFC 1951)
  — no header, no trailer, no Adler-32. Assembling a real RFC 1950 zlib stream (what
  `Content-Encoding: deflate` needs on the wire) means wrapping that raw output by hand. Caught by
  writing a standalone round-trip script and watching `NSData.decompressed(using: .zlib)` fail on
  the hand-wrapped output — decoding it for real needs genuine zlib `inflate()`, not the
  `Compression` framework's same-named-but-different algorithm. The same raw-deflate output is
  also what a real gzip container wraps (different header/trailer, same underlying bytes) —
  confirmed valid by writing actual `.gz` files and checking them with the system `gunzip -t`
  rather than trusting the RFC 1952 spec alone. See `PortableDeflateCompressorStream`'s and
  `PortableGzipCompressorStream`'s doc comments.
- **A report classifying a file as "bucket A, no work needed" is not the same as that file
  actually being gated.** `Internals.NIOTrustEvaluator.swift` was called out as "legitimately
  `.nio`-only forever, no work needed" as far back as the original audit — and still had a bare,
  unconditional `import NIOCore`/`import NIOSSL` at the top, never wrapped, until this session's
  forced-build pass actually tried to compile without it and failed. The same was true of
  `Internals.Session`/`Client`/`ClientResponseReceiver`/`UnsafeTask`/several others. Only a real
  attempt at the thing this file is working toward — forcing every gate to its `#else` branch and
  compiling — reliably finds this class of gap; a classification written down in a doc comment or
  a report, however confident, doesn't compile anything.
- **A NIOSSL-only file can be a dependency's dependency without ever writing `import NIOSSL`
  itself.** `Internals.ServerTrustPolicy.swift`, `Internals.ClientIdentityDescriptor.swift`, and
  `.urlSession`'s own `TLSVersion.urlSessionProtocolVersion` conversion all called a method
  (`resolvedCertificates()`/`CertificateChain.build()`/`NIOSSL.TLSVersion.urlSessionProtocolVersion`)
  whose *return type* was NIOSSL-defined, without the calling file ever spelling out `import
  NIOSSL` — Swift resolves member access on an already-typed value without requiring its
  declaring module imported into the calling file. `grep -l "^import NIOSSL"` misses this
  category entirely; only actually gating the callee and watching the caller fail to compile
  surfaces it.
- **Before trusting a third-party package's dependency graph, read its actual `Package.swift`.**
  `SwiftASN1`/`X509` (`swift-certificates`) turned out to have zero NIOCore/NIOSSL in their own
  dependency tree — confirmed by reading `.build/checkouts/swift-certificates/Package.swift`
  directly, not assumed from "it's used somewhere in a NIO-heavy codebase" — which is what made
  routing the portable certificate/SPKI work through them safe to do at all.
