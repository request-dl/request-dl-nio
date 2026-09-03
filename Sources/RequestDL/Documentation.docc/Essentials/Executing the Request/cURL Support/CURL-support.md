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
- `-H` / `--header` (repeatable)
- `-d` / `--data` / `--data-raw` / `--data-binary`
- `-F` / `--form` (repeatable) — `name=value`, or `name=@path;type=mime` for a file
- `-u` / `--user` (basic auth)
- `--url`, or a bare trailing URL
- `-G` / `--get` — moves accumulated `-d` data onto the URL as a query string instead of a body

Session-level — these configure the same `Session`-level settings a declared `@PropertyBuilder` tree would reach through ``RequestDL/Session``/``RequestDL/SecureConnection``/``RequestDL/Proxy``:

- `-L` / `--location` (with `--max-redirs`) — follows redirects, up to 50 by default
- `-k` / `--insecure` — disables certificate verification
- `-x` / `--proxy` — `[scheme://][user[:password]@]host[:port]`; a `socks*` scheme maps to a SOCKS proxy, anything else to HTTP; defaults to port 1080
- `--resolve HOST:PORT:ADDRESS` — overrides DNS resolution for `HOST` (the port is validated but not carried through — the override applies to every port on that host)
- `--compressed` — enables (unbounded) response decompression
- `--cacert <path>` — a custom CA bundle to verify the server against, in place of the default trust store
- `--cert <path>` / `-E <path>` (with `--key <path>`) — a client certificate (and its private key) for mTLS; both are read as PEM

`-L` and `--compressed` don't just add an opt-in: whenever *any* session-level flag is present, the produced description also **explicitly disables** redirects and decompression unless `-L`/`--compressed` say otherwise — this package normally follows redirects and (on Apple platforms) auto-decompresses by default, the opposite of curl's own defaults, so matching curl faithfully means actively turning both off, not just leaving this package's defaults in place. A command using none of these session-level flags is unaffected by this and behaves exactly as before they existed.

`--resolve` (`dnsOverride`) is incompatible with the `.urlSession` executor — a command using it only runs under `.nio`/`.nioTransportServices`.

### What isn't supported, and why

Everything else — cookie jars, `--cert-type`/`--key-type` (PEM is assumed), `--proxy-user`, HTTP/3, and non-`http(s)` schemes — throws ``RequestDL/CURLParsingError`` rather than being silently accepted. These aren't just unimplemented conveniences: silently accepting one of them would make the request actually performed diverge from what the command says.

## Topics

### Executing a curl command

- ``RequestDL/CURLTask``
- ``RequestDL/CURLParsingError``

### Describing a request as curl

- ``RequestDL/TaskDescriptor``
- ``RequestDL/TaskDescriptorContext``
- ``RequestDL/FormFieldDescriptor``
- ``RequestDL/CURLTaskDescriptor``
