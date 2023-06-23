# Using Swift Concurrency from beginning

Discover all the available resources to use async/await from the beginning.

## Overview

Built from the ground up with async/await in mind, RequestDL always internally uses asynchronous operations, thread locks, and Sendable.

SwiftNIO and AsyncHTTPClient also constantly send and receive request data in packets, including both headers and the body.

By combining the concepts of async/await with the tools provided by SwiftNIO and AsyncHTTPClient, the concept of steps represented by ``RequestDL/UploadStep``, ``RequestDL/DownloadStep``, and ``RequestDL/ResponseStep`` was implemented.

### Building the request

Although the focus is on using async/await in request execution, it is also possible to use asynchronous code during request specification.

Designed for cases when we have a service that is used only to specify a request field, the need for an object that provides such support arose.

```swift
struct GithubAPI: Property {

    var body: some Property {
        // Github API common properties
        AsyncProperty {
            Authorization(.bearer, token: try await tokenService.getToken())
        }
    }
}
```

This code allows us not only to use `await` during request specification, but also `try`.

### Executing the request

``RequestTask`` has some flexibility regarding the `Element` returned in the ``RequestTask/result()`` method execution. This enabled the implementation of ``RequestDL/UploadTask``, ``RequestDL/DownloadTask``, and ``RequestDL/DataTask``.

> Tip: Learn more about tasks in [Exploring the task diversity](<doc:Exploring-task>).

``RequestDL/AsyncResponse`` is the central object of the request. With it, we obtain the steps to know the amount of bytes sent and the bytes we are receiving.

``RequestDL/AsyncBytes`` informs us of the amount of bytes received asynchronously and also allows us to know the amount we will receive through the ``RequestDL/AsyncBytes/totalSize`` property.

> Important: Both objects are an `AsyncSequence` and should be used in a `for try await _` loop.

### Points of attention

``RequestDL/AsyncResponse`` and ``RequestDL/AsyncBytes`` objects work as an open stream that receives data regardless of who is listening.

In addition, each received element is inserted into a queue that remains available until the asynchronous object ceases to exist. Therefore, it is possible to have numerous `for try await _` loops in the code to observe the sequences as many times as necessary.

> Warning: Once the ``RequestDL/AsyncResponse`` and ``RequestDL/AsyncBytes`` objects cease to exist during a request, this may result in the operation being canceled.

## Topics

### Meet steps

- ``RequestDL/UploadStep``
- ``RequestDL/DownloadStep``
- ``RequestDL/ResponseStep``

### Discover the sequences

- ``RequestDL/AsyncResponse``
- ``RequestDL/AsyncBytes``
