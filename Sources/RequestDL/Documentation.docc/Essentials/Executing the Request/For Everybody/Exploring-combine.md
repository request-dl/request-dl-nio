# Exploring Combine support

Explore how to use Combine with tasks in an easy and efficient manner.

## Overview

RequestDL provides support for using Combine directly in the execution of requests. You can combine a series of `Modifiers` and `Interceptors` to finalize the request construction with ``RequestDL/RequestTask/publisher()``.

The only difference between an async/await request and one using Combine is the method used to finalize the request construction. This is possible thanks to the full integration of the base resources implemented for ``RequestDL/RequestTask``.

```swift
func userDetails() -> PublishedTask<User> {
    DataTask {
        // The request specifications
    }
    .logInConsole(true)
    .extractPayload()
    .keyPath(\.results)
    .decode(User.self)
    .publisher()
}
```

## Topics

### Meet the modifier

- ``RequestDL/PublishedTask``
- ``RequestDL/RequestTask/publisher()``
