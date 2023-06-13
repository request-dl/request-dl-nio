# ``RequestDL``

A network layer written in Swift based on the declarative programming paradigm.

## Overview

RequestDL aims to provide a comprehensive API for developing applications that consume network services. At its core, RequestDL is built on Apple's **AsyncHTTPClient**, which in turn is based on **SwiftNIO**.

With these foundations and leveraging modern networking techniques, along with extensive integration provided by Apple through these two modules, RequestDL can accomplish a great deal. All of this is achieved using a simplified and concise syntax.

## Where to start?

RequestDL is divided into two main parts: (a) ``RequestDL/Property``; and (b) ``RequestDL/RequestTask``.

### The Property protocol

This part is related to request construction, providing various methods and objects to specify the URL, payload, and headers. The `Property` utilizes the opaque type `some` to allow the implementation of declarative blocks that are compiled with the help of ``RequestDL/PropertyBuilder``, an `@resultBuilder`.

Example:

```swift
@PropertyBuilder
func appleWebsite() -> some Property {
    BaseURL("apple.com")

    RequestMethod(.post)
    AcceptHeader(.json)

    Payload(verbatim: "Hello Apple!")
}
```

Thanks to `SwiftNIO` and `AsyncHTTPClient`, we can highlight the following objects:

- ``RequestDL/Session``;
- ``RequestDL/SecureConnection``;
- ``RequestDL/Form``;
- ``RequestDL/ReadingMode``.

As for the methods:

- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:suiteName:)``;
- ``RequestDL/Property/urlEncoder(_:)``;
- ``RequestDL/Property/payloadPartLength(_:)``;

### The RequestTask protocol

This protocol is part of the request result processing. Thanks to async/await, we have the possibility of receiving the data through an `AsyncSequence` as well as the `Data` containing the raw bytes. Additionally, we can use ``RequestDL/RequestTaskModifier`` and ``RequestDL/RequestTaskInterceptor`` to perform various types of operations. The request is finalized using the ``RequestDL/RequestTask/result()`` method.

Example:

```swift
try await DataTask {
    BaseURL("apple.com")
    // Other properties
}
.result()
```

We have the following tasks:

- ``RequestDL/UploadTask``;
- ``RequestDL/DownloadTask``;
- ``RequestDL/DataTask``.

And the methods to add modifiers and interceptors:

- ``RequestDL/RequestTask/modifier(_:)``;
- ``RequestDL/RequestTask/interceptor(_:)``.

### Features

- [x] [Declarative request builder](<doc:Creating-requests-from-scratch>);
- [x] [mTLS / TLS / SSL / PSK](<doc:Secure-connection>);
- [x] [JSON / Codable / Multipart / URL Encoded](<doc:Exploring-payload>);
- [x] [UploadTask / DownloadTask / DataTask / MockedTask](<doc:Exploring-task>);
- [x] [Modifiers & Interceptors](<doc:Modifiers-and-Interceptors>); 
- [x] [Upload & Download progress](<doc:Upload-and-download-progress>);
- [x] [Swift Concurrency](<doc:Swift-concurrency>);
- [x] [Combine support](<doc:Exploring-combine>);

We are excited to expand this list with many other features. Start by making your contribution in [Discussions](https://github.com/orgs/request-dl/discussions) or by opening a PR (Pull Request).

---

## Topics

### First steps

- <doc:Creating-the-project-property>
- <doc:Preparing-the-certificates>

### Essentials

- <doc:Building-the-request>
- <doc:Executing-the-request>
