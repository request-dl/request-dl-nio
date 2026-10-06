# Emitting metrics

Report how long each request took, and how much it sent and received, to a `swift-metrics` backend by opting a session into a `MetricsFactory`.

## Overview

Reporting is opt-in per session, not ambient: a request is only reported when its session has been given a factory with ``RequestDL/Session/metricsFactory(_:)``. Without one nothing is reported, regardless of whether some other part of the process has bootstrapped a backend with `MetricsSystem.bootstrap(_:)`. To use that one, pass it explicitly.

```swift
DataTask {
    BaseURL("example.com")
    Session().metricsFactory(MetricsSystem.factory)
}
```

This is for aggregate observability, the counts and the percentiles over many requests. To read the phases of one request (DNS, connection, TLS, time to first byte), see ``RequestDL/RequestMetrics`` and <doc:Monitoring-requests>.

### What is reported

One measurement per execution, taken when it ends, so a request that follows redirects is one, and so is a download that reconnects. A request that fails is reported too, whichever executor sent it, and one that is suspended counts the time it was suspended.

| Metric | Kind | What it is |
| --- | --- | --- |
| `http.client.request.duration` | `Timer` | The time the execution took. `swift-metrics` records a `Timer` in nanoseconds. |
| `http.client.request.body.size` | `Recorder` | The bytes of the request body sent. Only for a request that has a body. |
| `http.client.response.body.size` | `Recorder` | The bytes of the response body received. Only for a request that got a response. |

The names follow the OpenTelemetry HTTP client metrics.

### Labels

| Label | Value |
| --- | --- |
| `http.request.method` | The method, when HTTP defines it, or `_OTHER`. |
| `server.address` | The host the request was sent to. |
| `http.response.status_class` | `1xx` to `5xx`. Absent when there was no response. |
| `error.type` | Only on a request that failed: `timeout`, `cancelled`, or the name of the type of the error. |

The URL is never a label, in whole or in part: its path and its query can hold anything, and a label with one value per request is what takes a metrics backend down.

Where it differs from OpenTelemetry: the status is its class rather than its code, to keep the labels few, and there is no protocol version, since the `URLSession` executor still reports a nominal one.

### What is not reported

- A response served from the cache: nothing was sent, and what it took is not what a request takes. The conditional request that asked whether the cache still held is not reported either.
- A request that fails before there is a request to describe, while its properties are being resolved.

## Topics

### Configuring the session

- ``RequestDL/Session/metricsFactory(_:)``
