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

- [x] [Swift Concurrency](<doc:Swift-Concurrency>);
- [x] [Declarative request builder](<doc:Declarative-request-builder>);
- [x] [mTLS / TLS / SSL / PSK connection](<doc:Secure-Connection>) (easy setup);
- [x] [Payload diversity](<doc:Payload-Diversity>) (JSON / Encodable / Multipart / URL Encoded);
- [x] [Task diversity](<doc:Task-Diversity>) (UploadTask / DownloadTask / DataTask / MockedTask);
- [x] [Modifiers & Interceptors](<doc:Modifiers-&-Interceptors>); 
- [x] [Upload & Download progress](<doc:Upload-&-Download-progress>);
- [x] [Combine support](<doc:Combine-Support>);

We are excited to expand this list with many other features. Start by making your contribution in [Discussions](https://github.com/orgs/request-dl/discussions) or by opening a PR (Pull Request).

## Why the Tucano bird?

![Brazilian AI generated Tucano bird](tucano.png)

The Request library, initially developed by Carson Katri in 2019, served as the foundation for RequestDL. However, in 2020, Brenno de Moura made contributions that eventually led to the point (2022) where he requested permission from Carson to continue the work independently, focusing on developing new features.

RequestDL originated in Brazil 🇧🇷, and as a tribute to the country, the Tucano bird, which is a common symbol found in Brazilian brands, was chosen as its mascot. Embracing the advancements in technology in 2023, the artwork for RequestDL was created using the text-to-image generator feature of the Canvas software.
