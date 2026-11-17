# Using a Client Certificate with the URLSession Executor

Set up the one-time Xcode project capability an app needs before a client certificate can be presented over the `.urlSession` executor.

# Using a Client Certificate with the URLSession Executor

Present a client certificate (mTLS) over the `.urlSession` executor, which needs no Xcode capability, no signing and no Keychain access.

## Overview

Your RequestDL code does not change at all. `SecureConnection { Certificates { Certificate(...) }; PrivateKey(...) }` keeps working exactly as documented in <doc:Preparing-the-certificates> and <doc:Secure-connection>, whichever executor the request ends up running over.

`.urlSession` is RequestDL's own default executor preference on Darwin whenever a session's configuration is compatible with it, so a request using ``Certificate``/``PrivateKey`` with no executor modifier at all may already be running over `.urlSession`. The same identity serves ``Session/Executor/nioTransportServices`` (Network.framework).

### How the identity is built

RequestDL turns your certificate and private key into the identity `URLSession` presents during the handshake **in memory**, pairing the two with `SecIdentityCreate`. Nothing is written to, read from or deleted from any Keychain. The private key lives only as long as the request's session (or the background download that needs it) holds the identity, and goes with it.

This has consequences worth knowing:

- **No Keychain Sharing capability and no entitlement.** An unsigned command-line tool, a `swift test` run, a signed app without Keychain Sharing and every Simulator all work the same.
- **No Keychain cleanup, and no interference between processes.** The macOS login keychain is shared by every process of the same user; since RequestDL stores nothing there, your app, its extensions and any other process using the same certificate cannot delete what another one is using.
- **EC client certificates work everywhere.** P-256, P-384 and P-521 keys (SEC1 or PKCS#8) are presented like RSA ones, including on macOS in a process with no signing at all.

## What you need to do

Nothing beyond configuring the certificate and the key, as always. In particular you do **not** need to:

- Add **Keychain Sharing** (or any `keychain-access-groups` entitlement) to any target, the app or an extension.
- Sign the app any specific way: no `codesign --entitlements` step, no provisioning profile requirement for this feature.
- Convert to PKCS#12: RequestDL keeps accepting raw PEM/DER bytes or file paths.
- Clean up anything in the Keychain.

## Items left by earlier versions

Versions of RequestDL before this change stored the client certificate and private key in the Keychain (items labelled `RequestDL.mtls.…`) and removed them when the session ended. Nothing reads them any more, but one that an earlier version could not remove (the process was killed, or another process was still using it) can still be there. Removing them is optional and harmless:

1. Open **Keychain Access** and select the **login** keychain.
2. Search for `RequestDL.mtls.`.
3. Delete the matching **keys** and **certificates**. Items of an app that is still on an older version are recreated by that version, so do this after every copy of your app is updated.

## Platforms

The in-memory identity is a public API on every platform RequestDL supports (`SecIdentityCreate`: macOS 10.12, iOS 11.2, tvOS 11.2, watchOS 4.2, visionOS 1.0).

Validated with a real mTLS handshake, RSA and EC P-256, over `URLSession` and over Network.framework on macOS, in an unsigned process with no entitlements. The same tests run on the iOS, tvOS and watchOS Simulators in CI. Not separately validated on a physical device, or on macOS 12–14 and iOS 15–17.

## Troubleshooting

A request using ``Certificate``/``PrivateKey`` that cannot build a client identity throws ``ClientIdentityError``; `error.reason` names the specific cause, and both `"\(error)"`/`error.description` and `error.localizedDescription` carry the same text.

- `.reason == .keyCreationFailed(message:)` with *"it is not the private key of the configured certificate"*: the key you configured is not the one of the certificate (their public keys differ). Check that both files come from the same pair.
- `.reason == .unsupportedKeyFormat(header:)`: the key is not RSA (PKCS#1 or PKCS#8) or EC P-256/P-384/P-521 (SEC1 or PKCS#8), or it is password-protected in a shape RequestDL cannot decrypt. See <doc:Preparing-the-certificates>.
- `.reason == .invalidCertificateData`: the certificate bytes are not a certificate.

``ClientIdentityError/Reason/missingKeychainSharingEntitlement(operation:)``, ``ClientIdentityError/Reason/keychainOperationFailed(operation:status:)`` and ``ClientIdentityError/Reason/identityLookupReturnedWrongType`` are no longer thrown; they remain only so existing `switch` statements keep compiling.

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
