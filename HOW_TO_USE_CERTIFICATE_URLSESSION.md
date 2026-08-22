# Using `Certificate`/`PrivateKey` (mTLS) once the URLSession executor lands

**Status:** the TLS/mTLS mapping this document describes is implemented (`URLSESSION_TASK.md` Phase 5e — `Internals.RawBytesIdentityBuilder`, `Internals.URLSessionIdentityPolicy`), but there is no public API yet to select the URLSession executor for a request (Phases 6/7). This still covers the one thing an app developer will need to do differently once that lands, based on the validated spike for [request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287). See [URLSESSION_REPORT.md](URLSESSION_REPORT.md) for the full technical background.

**The short version:** your RequestDL code does not change at all. `SecureConnection { Certificates { Certificate(...) }; PrivateKey(...) }` keeps working exactly as documented in [Preparing the Certificates](Sources/RequestDL/Documentation.docc/First%20steps/Preparing-the-certificates.md). The one thing that changes is a **one-time Xcode project setting** — enabling Keychain Sharing — because that's what lets RequestDL turn your raw certificate/key bytes into something URLSession can present during an mTLS handshake.

---

## Why this is needed at all

There is no public API on Apple platforms to hand URLSession a client identity built purely from bytes in memory. The only path is a Keychain round-trip: write the private key into the Keychain, then look it up again paired with the certificate as a `SecIdentity`. Writing a key into the Keychain requires the app to carry a `keychain-access-groups` entitlement — without it, the write fails with `OSStatus -34018` (`errSecMissingEntitlement`).

This is **not** optional configuration you can skip if you don't need it and it's not something RequestDL can work around internally — it's an OS-level requirement for any app that writes key material into the Keychain, on iOS, iPadOS, tvOS, and watchOS alike.

## What you need to do

### 1. Enable Keychain Sharing in Xcode

For every target that runs code using `Certificate`/`PrivateKey` for mTLS (your main app target, and any app extension that does the same — see below):

1. Select the target in your project's **Signing & Capabilities** tab.
2. Click **+ Capability**.
3. Add **Keychain Sharing**.

That's it. Xcode adds (or updates) a `.entitlements` file for you with:

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
</array>
```

You don't need to edit this by hand, name a specific group, or register anything extra on the Apple Developer portal — the default, auto-generated group (your own app's identifier) is exactly what RequestDL needs. Registering additional named groups only matters if you're sharing Keychain items *across multiple apps from the same team*, which is unrelated to this.

### 2. Sign the app the normal way

**No manual `codesign` step, no hand-written entitlements plist, no special account type.** Whatever you already do to sign and run your app is enough:

- Running on the Simulator — Xcode's own "Sign to Run Locally" identity works.
- Running on a physical device with a free/individual Apple ID, a paid Developer Program membership, or an Enterprise account — all validated during this spike, all worked identically once Keychain Sharing was enabled.
- Building via CI (`xcodebuild`, `fastlane`, etc.) with a real signing identity and provisioning profile — as long as the `.entitlements` file with Keychain Sharing is checked into the project (it is, once you've done step 1 and committed the result), no extra CI-specific configuration is needed.

If you find yourself reaching for a manual `codesign --entitlements ...` invocation to "fix" a Keychain error, that's a sign something upstream is wrong (see Troubleshooting) — it is not a normal part of using this feature. Entitlements only take effect when they're sealed into the binary by a trusted signing identity as part of the regular build; stapling them on afterward with a bare `codesign` call does not work and, on device, will fail to even launch.

## What you do *not* need to do

- No changes to your `SecureConnection`/`Certificates`/`PrivateKey`/`TrustRoots` code.
- No PKCS#12 conversion — RequestDL keeps accepting raw PEM/DER bytes or file paths exactly as today.
- No manual Keychain cleanup — RequestDL owns the lifecycle of the identity it builds internally.
- No portal-level "App ID capability" registration for the default, single-app access group.

## Platforms

Validated end to end (Keychain round-trip + a real mTLS-shaped request through `URLSession`) on:

- iOS Simulator, via a properly Xcode-signed build ("Sign to Run Locally"). Reconfirmed independently against the promoted, shipping `Internals.RawBytesIdentityBuilder` (not just the original spike) via a throwaway Xcode project — `SecItemCopyMatching(identity) returned 1 identities`, i.e. the pairing genuinely succeeds once Keychain Sharing is added. See `URLSESSION_TASK.md` Phase 5e's acceptance section for the exact steps.
- A physical iOS device, signed under a corporate/enterprise Apple Developer team.

Not yet separately validated, treat with more caution until confirmed:

- **tvOS / watchOS** — same Keychain model as iOS (single data-protection keychain, same entitlement requirement), so this is expected to behave identically, but hasn't been physically tested.
- **macOS, sandboxed (Mac App Store) apps** — expected to need the same Keychain Sharing capability as iOS.
- **macOS, non-sandboxed apps** (plain command-line tools, non-App-Store apps) — confirmed broken, not just "uncertain": an unsigned command-line process (`swift test`) reliably hits `SecItemCopyMatching(kSecClassIdentity)` returning zero results (`errSecItemNotFound`) after `SecItemAdd` succeeds for the certificate and key individually — i.e. exactly the pairing failure this section originally flagged as unresolved, now reproduced with specifics rather than left as a guess. Separate from, and not fixed by, the entitlement issue this document addresses (the process has no `keychain-access-groups` entitlement to add in the first place, being a bare CLI binary). Don't assume this works on non-sandboxed macOS.

## Troubleshooting

**`OSStatus -34018` / `errSecMissingEntitlement` when a request using `Certificate`/`PrivateKey` runs:**

1. Confirm Keychain Sharing is listed under Signing & Capabilities for the target that's actually running (check app extensions separately — each target has its own entitlements).
2. Confirm you're not post-processing or re-signing the built app with a separate `codesign` step that doesn't carry the same entitlements forward.
3. Confirm the build is actually using a signing identity (Team set, not "None") — an app with no signing identity at all can still launch in some contexts but won't have any entitlements applied.

**A client-certificate-requiring server returns an HTTP error (e.g. 400) instead of a TLS-level failure:** that's usually not a RequestDL/entitlement problem — it means the handshake completed and your identity was presented, but the server didn't accept *that specific* certificate (wrong CA, expired, wrong host). Confirm the certificate/key pair you configured is the one the server actually expects.

## App extensions

If a share extension, widget, or other extension target also makes requests using `Certificate`/`PrivateKey`, it needs its **own** Keychain Sharing capability enabled — entitlements are per-target in Xcode, not inherited from the containing app.

---

## Reference implementation

The Keychain round-trip and `URLSessionDelegate` wiring this relies on were validated with a small standalone spike, not yet merged into RequestDL itself:

- Discussion: [request-dl-nio#287](https://github.com/request-dl/request-dl-nio/discussions/287)
- Technical mapping: [URLSESSION_REPORT.md](URLSESSION_REPORT.md), §5.1 and the "Executor resolution model" section
