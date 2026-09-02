# Distributed tracing

Record a distributed-tracing span for a request by opting a session into a `Tracer` and, optionally, binding the `ServiceContext` it should be a child of.

## Overview

Tracing is opt-in per session, not ambient: a request only produces a span when its session has been given a `Tracer` via ``RequestDL/Session/tracer(_:)``. Without one, the session falls back to a no-op tracer, regardless of whether some other part of the process has globally bootstrapped an instrumentation backend.

```swift
DataTask {
    BaseURL("example.com")
    Session().tracer(myTracer)
}
```

RequestDL owns the whole span lifecycle itself — starting the span, injecting W3C trace headers, setting attributes, and ending it — rather than delegating to `async-http-client`'s own tracing configuration. That's what makes it possible to bind a specific `ServiceContext` to a single request and have the started span actually pick it up as its parent.

### Binding a ServiceContext

Use ``RequestDL/RequestServiceContext`` to bind a `ServiceContext` to a request, overriding whatever `ServiceContext.current` task-local happens to be ambient at the point the request executes:

```swift
DataTask {
    BaseURL("example.com")
    Session().tracer(myTracer)
    RequestServiceContext(context)
}
```

## Topics

### Configuring the session

- ``RequestDL/Session/tracer(_:)``

### Binding a ServiceContext

- ``RequestDL/RequestServiceContext``
