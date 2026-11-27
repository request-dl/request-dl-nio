# Using a Client Certificate with the URLSession Executor

Present a client certificate (mTLS) over the `.urlSession` executor, which needs no Xcode capability, no signing and no Keychain access.

## Overview

Your RequestDL code does not change at all. `SecureConnection { Certificates { Certificate(...) }; PrivateKey(...) }` keeps working exactly as documented in <doc:Preparing-the-certificates> and <doc:Secure-connection>, whichever executor the request ends up running over.

`.urlSession` is RequestDL's own default executor preference on Darwin whenever a session's configuration is compatible with it, so a request using ``Certificate``/``PrivateKey`` with no executor modifier at all may already be running over `.urlSession`. The same identity serves ``Session/Executor/nioTransportServices`` (Network.framework).

### How the identity is built

RequestDL turns your certificate and private key into the identity `URLSession` presents during the handshake **in memory**, pairing the two with `SecIdentityCreate`. Nothing is written to, read from or deleted from any Keychain. The private key is held by the identity, so it stays in memory for as long as `URLSession` or Network.framework still use it (a short while after the session ends) and is released after that. RequestDL does not wipe the memory the key was parsed from. The Keychain's "accessible only while unlocked" protection no longer applies either: the key is as protected as the certificate and key files you configured, so a background download with a client certificate can also run while the device is locked.

This has consequences worth knowing:

- **No Keychain Sharing capability and no entitlement.** An unsigned command-line tool, a `swift test` run, a signed app without Keychain Sharing and every Simulator all work the same.
- **Nothing to clean up, and no interference between processes.** The macOS login keychain is shared by every process of the same user; since RequestDL stores nothing there, your app, its extensions and any other process using the same certificate cannot delete what another one is using.
- **EC client certificates work on macOS without signing.** P-256, P-384 and P-521 keys (SEC1 or PKCS#8) are paired like RSA ones, including on macOS in a process with no signing at all (the old Keychain path could not store an imported EC key there). The handshake was exercised with P-256.

### Certificate chains with intermediates

When your client certificate is issued by an intermediate authority, configure the whole chain: the client certificate first, then the intermediates, as one PEM file or as several ``Certificate`` values inside ``Certificates``. RequestDL presents the leaf as the identity and the rest alongside it, on every executor:

- `.urlSession` hands the intermediates to the `URLCredential` it answers the server's challenge with.
- `.nio` gives all of them to NIOSSL.
- `.nioTransportServices` (Network.framework) presents them through `sec_identity_create_with_certificates`, which AsyncHTTPClient calls when the identity carries intermediates.

A server that trusts only the root authority therefore accepts the handshake on all three, without having the intermediate in its own trust store. The root itself is normally left out of what you configure, as the server already has it; including it is harmless.

Earlier versions could not do this under `.nioTransportServices`: a chain with more than one certificate made RequestDL refuse that executor, with ``ExecutorRequirementError/Reason/multipleClientCertificatesUnderNetworkFramework`` when you pinned it, or fall back to `.urlSession` when you only preferred it. That is gone: the reason is never produced any more and is deprecated, and a chain with intermediates keeps `.nioTransportServices` eligible. A `switch` over ``ExecutorRequirementError/Reason`` can drop it.

## What you need to do

Nothing beyond configuring the certificate and the key, as always. In particular you do **not** need to:

- Add **Keychain Sharing** (or any `keychain-access-groups` entitlement) to any target, the app or an extension.
- Sign the app any specific way: no `codesign --entitlements` step, no provisioning profile requirement for this feature.
- Convert to PKCS#12: RequestDL keeps accepting raw PEM/DER bytes or file paths.
- Clean up anything in the Keychain yourself, unless you want to remove what a version before this one left in the macOS login keychain (see below).

## Items left by earlier versions

Versions of RequestDL before this change stored the client certificate and private key in the Keychain (items labelled `RequestDL.mtls.…`) and removed them when the session ended. Nothing reads them any more, but one that an earlier version could not remove (the process was killed before it could, or another process was still using it) can still be there.

### In the data-protection keychain: removed automatically

A signed app that could use the data-protection keychain (on macOS, one with Keychain Sharing), and an app on iOS, tvOS, watchOS or visionOS, stored them there. The first time a client identity is built in a process, RequestDL looks there, in the background and without delaying the request, and removes the **private keys** an earlier version left. It removes one only when all of this holds:

- it is a key (never a certificate), in the data-protection keychain this process can see (the access groups of your own app, which include any group it shares with other apps of your team);
- its label is exactly `RequestDL.mtls.key.` followed by 40 lowercase hex digits that are the hash of the key's own public key, or by 64 lowercase hex digits on a key that has a 20-byte application label (the first versions' label);
- it was created more than 24 hours ago, so it is very unlikely to be one that an older copy of your app, or another app of your team sharing the keychain group, is using right now (an older version that is still running can still be using a key made more than a day ago: it reuses an existing key instead of making a new one, so the key's age says when it was first made, not when it was last used). An item with no creation date is kept.

An older version that is still running when this cleanup removes a key it is using can fail more than one request. That version builds the identity once and keeps it for as long as its client or session lives, so if the system needs the keychain item to sign with the key, every new handshake from that client can fail until the client is created again (for example when the app or extension that runs it is restarted). Whether the system needs the item was seen in the legacy macOS keychain; for the data-protection keychain it has not been checked on a device, so treat the single failed request as the best case, not as a guarantee. To avoid it, update every app and extension that shares the keychain group.

It never touches certificates (they are public data, and an equal certificate may be yours), items that this process cannot see, or any key whose label does not match exactly. Keys of another app of your team in a keychain group shared with this one are visible to this process: only the ones that match all of the above are removed. If Security answers that it would need the user (a prompt, a locked device), it stops. It is best effort: when the process lacks the entitlement, or anything fails, nothing is removed and nothing is reported, and the next process tries again. A leftover certificate stays in the keychain: RequestDL does not remove it.

### In the macOS login keychain: not removed

RequestDL does **not** clean the legacy macOS keychain. It is shared with every program of the user, an item there cannot be checked for its age, and nothing tells whose item it is. By hand, with **Keychain Access**, in the **login** keychain:

1. Search for `RequestDL.mtls.` and delete the matching **keys** (`RequestDL.mtls.key.…`).
2. The macOS file keychain did not store a label for the certificate, so a leftover certificate does not show up in that search: look for your client certificate by its name in the *Certificates* category and delete the copy RequestDL added, if you did not import it yourself.
3. Do this after every copy of your app is updated: one still on an older version recreates the items.

## Platforms

The in-memory identity is a public API on every platform RequestDL supports (`SecIdentityCreate`: macOS 10.12, iOS 11.2, tvOS 11.2, watchOS 4.2, visionOS 1.0).

Validated with a real mTLS handshake, RSA and EC P-256, over `URLSession` (foreground and background) on macOS, in an unsigned process with no entitlements. The iOS, tvOS and watchOS Simulators, a physical device, and macOS 12–14 / iOS 15–17 were not validated separately.

## Troubleshooting

A request using ``Certificate``/``PrivateKey`` that cannot build a client identity throws ``ClientIdentityError``; `error.reason` names the specific cause, and both `"\(error)"`/`error.description` and `error.localizedDescription` carry the same text.

- `.reason == .keyCreationFailed(message:)` with *"it is not the private key of the configured certificate"*: the key you configured is not the one of the certificate (their public keys differ). Check that both files come from the same pair. With *"unsupported algorithm or curve"*: the certificate's own public key is of a kind Security cannot read (RSA-PSS, brainpool, secp256k1); use an RSA or P-256/P-384/P-521 certificate.
- `.reason == .unsupportedKeyFormat(header:)`: the key is not RSA (PKCS#1 or PKCS#8) or EC P-256/P-384/P-521 (SEC1 or PKCS#8), or it is password-protected in a shape RequestDL cannot decrypt. See <doc:Preparing-the-certificates>.
- `.reason == .invalidCertificateData`: the certificate bytes are not a certificate.

``ClientIdentityError/Reason/missingKeychainSharingEntitlement(operation:)``, ``ClientIdentityError/Reason/keychainOperationFailed(operation:status:)`` and ``ClientIdentityError/Reason/identityLookupReturnedWrongType`` are no longer thrown and are deprecated; they remain only so existing `switch` statements keep compiling. A `switch` with a `default` can drop them; an exhaustive one cannot, because removing a case from it stops it from compiling ("switch must be exhaustive"), so keep them there until you move to a `default`.

**A client-certificate-requiring server returns an HTTP error (e.g. 400) instead of a TLS-level failure:** that's usually not a RequestDL problem. It means the handshake completed and your identity was presented, but the server didn't accept *that specific* certificate (wrong CA, expired, wrong host). Confirm the certificate/key pair you configured is the one the server actually expects.

## App extensions

Nothing is shared and nothing is stored, so a share extension, widget or other extension that also uses ``Certificate``/``PrivateKey`` needs no capability and cannot affect the app, or the other way around. Each process builds its own identity from the certificate and key it is configured with.

## Topics

### Errors

- ``ClientIdentityError``
- ``ExecutorRequirementError``

### Choosing an executor

- ``Session/preferredExecutor(_:)``
- ``Session/requiredExecutor(_:)``
