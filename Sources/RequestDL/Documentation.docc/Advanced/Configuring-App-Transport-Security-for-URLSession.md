# Configuring App Transport Security for the URLSession Executor

Adjust your app's Info.plist when a ``SecureConnection`` TLS policy needs to run over the `.urlSession` executor.

## Overview

`SecureConnection`'s TLS-version and ALPN modifiers — ``SecureConnection/version(minimum:)``, ``SecureConnection/version(maximum:)``, `version(_:)`, and ``SecureConnection/applicationProtocols(_:)`` — configure real, enforced behavior when a request runs over ``Session/Executor/nioTransportServices`` or the default non-Darwin executor: they're handed straight to SwiftNIO's TLS stack.

Under ``Session/Executor/urlSession`` the picture is split. `URLSessionConfiguration` exposes `tlsMinimumSupportedProtocolVersion` and `tlsMaximumSupportedProtocolVersion`, and RequestDL sets them from the TLS version range, so both ``SecureConnection/version(minimum:)`` and ``SecureConnection/version(maximum:)`` take effect there. It exposes nothing for an ALPN protocol list. On top of that, the OS enforces **App Transport Security (ATS)**, which your app declares once in its `Info.plist`, not per-request, and which RequestDL cannot relax for you.

RequestDL reacts differently to each of these:

- ``SecureConnection/applicationProtocols(_:)``, like `cipherSuites(_:)`, is treated as incompatible with `.urlSession`: automatic executor resolution skips `.urlSession` in favor of a NIO-based executor when it is set, and pinning to `.urlSession` explicitly throws ``ExecutorRequirementError`` instead of silently dropping it. It has no ATS key at all, so there's no Info.plist fix; see [What ATS cannot do](#What-ATS-cannot-do).
- ``SecureConnection/version(maximum:)`` is applied to the `URLSessionConfiguration` and is *not* flagged as incompatible. ATS has no key for it and doesn't need one.
- ``SecureConnection/version(minimum:)`` is applied to the `URLSessionConfiguration` too, and is *not* flagged as incompatible. It can raise the floor (for example to TLS 1.3), but it cannot lower what ATS allows: below TLS 1.2 the connection is still refused until an ATS exception (`NSExceptionMinimumTLSVersion`) allows it. This article's [What you need to do](#What-you-need-to-do) section covers that exception.

`.urlSession` is also RequestDL's own default executor preference on Darwin whenever the rest of a session's configuration is compatible with it, so a request using ``SecureConnection`` with no executor modifier at all may already be running over `.urlSession`.

### Why this is needed at all

ATS is a system-wide policy, enforced by the OS before your app's TLS preferences ever come into play. By default it already requires TLS 1.2 or later and forward-secrecy cipher suites for every connection `URLSession` makes, and it blocks anything weaker outright rather than letting the request attempt a weaker handshake. RequestDL cannot lower or relax that policy on your behalf at request-construction time; there is no API surface for it. The only way to change what `URLSession` will allow is the same way any other Apple-platform app does it: an `NSAppTransportSecurity` dictionary in `Info.plist`, per Apple's [Cocoa Keys reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW35).

This cuts both ways. ATS's defaults are already at or above what `SecureConnection`'s own defaults require, so most requests need no Info.plist changes at all. Info.plist only comes into play when your `SecureConnection` configuration, or the server you're calling, needs something *outside* ATS's defaults, most commonly a minimum TLS version below 1.2, or a plain-HTTP endpoint.

## What you need to do

If a request's server needs a relaxed TLS policy and that request may run over `.urlSession`, add an ATS exception for that server's domain to your app's `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>example.com</key>
        <dict>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.1</string>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

The keys that map onto `SecureConnection`'s own modifiers:

| `SecureConnection` modifier | ATS `Info.plist` key | Scope |
| --- | --- | --- |
| ``SecureConnection/version(minimum:)`` below TLS 1.2 | `NSExceptionMinimumTLSVersion` | Per exception domain |
| Plain HTTP instead of HTTPS | `NSExceptionAllowsInsecureHTTPLoads` (or `NSAllowsArbitraryLoads` app-wide) | Per exception domain, or global |

Set `NSIncludesSubdomains` to match whichever domains the request actually targets, and scope the exception as narrowly as possible. App Store review, and your own users' security, are both better served by a domain-specific exception than a blanket `NSAllowsArbitraryLoads`.

## What ATS cannot do

`SecureConnection`'s ALPN modifier has **no** ATS equivalent at all, under any Info.plist configuration, and no `URLSessionConfiguration` property either. This is exactly why RequestDL flags it as incompatible with `.urlSession` instead of leaving it to fail silently:

- ``SecureConnection/applicationProtocols(_:)`` (ALPN, deprecated): `URLSession` negotiates ALPN automatically (HTTP/2 vs. HTTP/1.1) and Info.plist has no key to override the protocol list it offers. To keep a session off HTTP/2, use ``Session/httpVersion(_:)`` with ``Session/HTTPVersion/http1Only``, which is treated the same way: it routes the session away from `.urlSession`.

If a request depends on it, it needs an executor that actually enforces it: ``Session/preferredExecutor(_:)`` or ``Session/requiredExecutor(_:)`` with ``Session/Executor/nioTransportServices`` (or the default non-Darwin executor) instead of `.urlSession`. Under automatic resolution (no executor pinned) this already happens for you; pinning to `.urlSession` anyway makes the conflict explicit via ``ExecutorRequirementError`` rather than silently dropping the setting.

## What you do not need to do

- No changes to your `SecureConnection` code. The same modifiers are still what non-`.urlSession` executors read.
- No per-request Info.plist manipulation. ATS exceptions are declared once, at the app level.
- No Info.plist changes at all for requests whose TLS requirements already sit within ATS's defaults (TLS 1.2+, forward secrecy), which is the common case.

## Platforms

ATS applies to `URLSession` on iOS, iPadOS, tvOS, watchOS, and macOS alike. It does not apply to the non-`.urlSession` executors (``Session/Executor/nioTransportServices``, the default non-Darwin executor), which read `SecureConnection`'s TLS-policy modifiers directly instead.

## Troubleshooting

A request that needs a minimum TLS version below TLS 1.2 (or plain HTTP) than ATS's defaults, running over `.urlSession` without a matching exception, fails at the transport level rather than reaching the server. This is commonly surfaced as an `NSURLErrorDomain` error with code `-1022` (`NSURLErrorAppTransportSecurityRequiresSecureConnection`), or a TLS handshake failure logged by the OS mentioning ATS. That failure happens below RequestDL, so no ``SecureConnection`` setting can catch or translate it; check the console log for the ATS-specific message, then add the matching exception domain above.

A request that sets ``SecureConnection/applicationProtocols(_:)`` never gets this far: RequestDL routes it away from `.urlSession` on its own (or throws ``ExecutorRequirementError`` if you pinned `.urlSession` explicitly), well before any ATS-level failure could occur. See [What ATS cannot do](#What-ATS-cannot-do).

## Topics

### Configuring TLS policy

- ``SecureConnection/version(minimum:)``
- ``SecureConnection/version(maximum:)``
- ``SecureConnection/applicationProtocols(_:)``

### Choosing an executor

- ``Session/preferredExecutor(_:)``
- ``Session/requiredExecutor(_:)``
- ``ExecutorRequirementError``
