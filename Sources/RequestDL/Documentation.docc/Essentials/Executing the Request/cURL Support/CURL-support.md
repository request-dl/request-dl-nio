# cURL support

Move between a declared request and its curl command line equivalent, in either direction.

## Overview

``RequestDL/CURLTask`` parses a curl command line and performs it as a request. ``RequestDL/TaskDescriptor`` — with ``RequestDL/CURLTaskDescriptor`` as its built-in `.cURL` conformance — goes the other way, producing the curl command line equivalent of a request declared with ``RequestDL/DataTask``, ``RequestDL/DownloadTask``, or ``RequestDL/UploadTask``.

Both directions understand the same documented subset of curl's flags — this isn't full curl compatibility, and flags outside that subset are rejected rather than silently ignored. See below for exactly what's covered and why the rest isn't.

### From curl to a request

```swift
let result = try await CURLTask("""
    curl -X POST https://example.com/users \\
        -H "Content-Type: application/json" \\
        -d '{"name":"John Doe"}'
    """
)
.result()
```

`CURLTask` parses the command straight into a ``RequestDL/RequestConfiguration`` — there's no `@PropertyBuilder` tree to declare from a string only known at runtime — but resolution and execution still go through the same pipeline ``RequestDL/DataTask`` uses, so caching, tracing, and executor requirements all apply exactly the same way.

> Important: Run only curl commands you wrote or trust. A command is a program for the request engine, not just data: `-F name=@path` uploads the local file it names, `--cert`, `--key` and `--cacert` read files from disk, `-k` / `--insecure` turns certificate verification off, and `-x` / `--proxy` and `--resolve` change where the request goes. A command assembled from user input, a pasted snippet or a network response can leak local files to a host of its choosing or remove TLS protection. Say what the command may do, as below, reject or inspect it first, or declare the request with ``RequestDL/DataTask`` instead.

### A command you do not control

``RequestDL/CURLTask/init(_:allowing:)`` takes the capabilities a command may use. A flag that needs one it was not given throws ``RequestDL/CURLParsingError`` with `unsupportedFlag` while the command is parsed, before any file is opened and before anything is sent:

```swift
// Nothing it could read, redirect or weaken.
try await CURLTask(pasted, allowing: [])
    .result()

// The same, but it may name a proxy.
try await CURLTask(pasted, allowing: .proxy)
    .result()
```

| Capability | Flags it covers |
|---|---|
| `.localFiles` | `-F name=@path` (relative paths too, which resolve against the working directory), `--cacert`, `--cert` / `-E`, `--key` |
| `.disabledTLSVerification` | `-k` / `--insecure` |
| `.proxy` | `-x` / `--proxy` |
| `.dnsOverrides` | `--resolve` |

Everything else in the subset (the method, headers, a body, a form of plain fields, `-u`, redirects, `--compressed`, and the flags that only shape curl's own output) needs none. `CURLTask(_:)` allows all of them, as it always did.

### From a request to curl

```swift
let command = try await DataTask {
    BaseURL("example.com")
    Path("users")
    RequestMethod(.post)
    CustomHeader(name: "Content-Type", value: "application/json")
    Payload(verbatim: #"{"name":"John Doe"}"#, contentType: .json)
}
.description(.cURL)
```

`.description(_:)` resolves the declared request the same way ``RequestDL/RequestTask/result()`` would, then hands the outcome to a ``RequestDL/TaskDescriptor`` instead of performing it over the network — nothing here touches a `Session` or the network at all. `.cURL` is only the first conformance: any type can adopt ``RequestDL/TaskDescriptor`` the same way it would ``RequestDL/RequestTaskModifier`` or ``RequestDL/RequestTaskInterceptor``, and pick up the same resolved request through ``RequestDL/TaskDescriptorContext``.

A declarative ``RequestDL/Form`` round-trips field by field, not as one flattened blob — each `-F` comes from the field captured before it was folded into the multipart body, which is the one place a resolved ``RequestDL/RequestConfiguration`` alone can't be read back from.

```swift
let command = try await DataTask {
    BaseURL("example.com")
    Form(name: "name", verbatim: "John Doe")
    Form(name: "avatar", filename: "avatar.png", contentType: .png, data: avatarData)
}
.description(.cURL)

// curl \
//   'https://example.com' \
//   -F 'name=John Doe' \
//   -F 'avatar=@avatar.png;type=image/png'
```

### Supported flags

Request-level — these shape the `RequestDL/RequestConfiguration` itself:

- `-X` / `--request`
- `-H` / `--header` (repeatable) — `-H 'Name:'` with no value removes the header, as in curl
- `-d` / `--data` / `--data-raw` / `--data-binary` — a value that starts with `@` (a file, or `@-` for stdin) is rejected, except for `--data-raw`, which sends it as text
- `-F` / `--form` (repeatable) — `name=value`, or `name=@path;type=mime` for a file; `name=<path` is rejected
- `--form-string` (repeatable) — `name=value`, the value as text: it is never read as a file, and `;type=` is not a parameter
- `-u` / `--user` (basic auth)
- `--url`, or a bare trailing URL
- `-G` / `--get` — moves accumulated `-d` data onto the URL as a query string instead of a body

Session-level — these configure the same `Session`-level settings a declared `@PropertyBuilder` tree would reach through ``RequestDL/Session``/``RequestDL/SecureConnection``/``RequestDL/Proxy``:

- `-L` / `--location` (with `--max-redirs`) — follows redirects, up to 50 by default; `--max-redirs -1` means no limit
- `-k` / `--insecure` — disables certificate verification
- `-x` / `--proxy` — `[scheme://][user[:password]@]host[:port]`; a `socks*` scheme maps to a SOCKS proxy, anything else to HTTP; defaults to port 1080
- `--socks5 <host[:port]>` / `--socks5-hostname <host[:port]>` — a SOCKS5 proxy named without a scheme (the same proxy `-x socks5://host[:port]` names; destinations are always sent to the proxy as names). A value that has a scheme of its own (`--socks5 socks5h://host`) is rejected: use `-x` for a proxy URL
- `-U` / `--proxy-user <user:password>` — the credentials of the proxy `-x`/`--socks5` names: `Proxy-Authorization` Basic for an HTTP proxy, the SOCKS5 user name and password (RFC 1929) for a SOCKS proxy. Credentials written in the proxy's own URL win over it, as in curl. It is an error without a proxy to apply to
- `--resolve HOST:PORT:ADDRESS` — overrides DNS resolution for `HOST` (the port is validated but not carried through — the override applies to every port on that host)
- `--compressed` — enables (unbounded) response decompression
- `--cacert <path>` — a custom CA bundle to verify the server against, in place of the default trust store
- `--cert <path>` / `-E <path>` (with `--key <path>`) — a client certificate (and its private key) for mTLS; both are read as PEM

`-L` and `--compressed` don't just add an opt-in: whenever *any* session-level flag is present, the produced description also **explicitly disables** redirects and decompression unless `-L`/`--compressed` say otherwise — this package normally follows redirects by default, the opposite of curl's own default, so matching curl faithfully means actively turning that off, not just leaving this package's defaults in place. Decompression is off by default on every platform now, matching curl's own default already, so `--compressed`'s absence needs no equivalent override there. A command using none of these session-level flags is unaffected by this and behaves exactly as before they existed.

**SOCKS5 credentials.** The user name and the password of a `socks*` proxy (`-x socks5://user:password@host`, or `-U`) are the ones SOCKS5 sends in clear text, 1 to 255 bytes for the user name and 0 to 255 for the password in UTF-8; outside of that, or with a NUL (`%00`) in either, or with a percent sequence that is not valid UTF-8 (`%FF`), the command is rejected with ``RequestDL/CURLParsingError`` (naming the flag that was typed, `-x`/`--proxy`, `--socks5`, `-U`/`--proxy-user`, and never the credentials, in this and in every other proxy error), and an empty password (`user:` or `user@host`) is allowed. Credentials inside a `socks*` proxy URL are percent-decoded, as curl does (`us%40er` is `us@er`); `-U` values are used as written, and so are the credentials of an HTTP proxy URL, as they always were. The proxy URL's host is taken as written, so an IPv6 address keeps its brackets (`socks5://u:p@[::1]:1080` has the host `[::1]`), as it always did for HTTP. Every `socks*` scheme, `socks4` and `socks4a` included, is spoken as SOCKS5, which is the only version that has a user name and a password to send. See ``RequestDL/Proxy`` for what a failed authentication does.

`--resolve` (`dnsOverride`) is incompatible with the `.urlSession` executor — a command using it only runs under `.nio`/`.nioTransportServices`.

### What isn't supported, and why

Everything else — cookie jars, `--cert-type`/`--key-type` (PEM is assumed), `--proxy-anyauth`/`--proxy-digest`/`--proxy-ntlm` and every other `--proxy-*` option (only `--proxy` and `--proxy-user` are understood), `--socks4`/`--socks4a`, HTTP/3, and any scheme other than `http` or `https` (`unix://`, `http+unix://`, `ftp://`, …) — throws ``RequestDL/CURLParsingError`` rather than being silently accepted. These aren't just unimplemented conveniences: silently accepting one of them would make the request actually performed diverge from what the command says.

## Topics

### Executing a curl command

- ``RequestDL/CURLTask``
- ``RequestDL/CURLParsingError``

### Describing a request as curl

- ``RequestDL/TaskDescriptor``
- ``RequestDL/TaskDescriptorContext``
- ``RequestDL/FormFieldDescriptor``
- ``RequestDL/CURLTaskDescriptor``
