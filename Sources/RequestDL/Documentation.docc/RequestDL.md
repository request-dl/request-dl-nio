# ``RequestDL``

A network layer written in Swift based on the declarative programming paradigm.

@Metadata {
    @PageImage(
        purpose: icon,
        source: "tucano",
        alt: "A technology icon representing the RequestDL framework.")

    @PageColor(blue)

    @Available(macOS, introduced: "12.0")
    @Available(iOS, introduced: "15.0")
    @Available(tvOS, introduced: "15.0")
    @Available(watchOS, introduced: "8.0")
    @Available("Swift", introduced: "6.2")

    @SupportedLanguage(swift)
}

## Overview

RequestDL aims to provide a comprehensive API for developing applications that consume network services. At its core, RequestDL is built on Apple's **AsyncHTTPClient**, which in turn is based on **SwiftNIO**.

With these foundations and leveraging modern networking techniques, along with extensive integration provided by Apple through these two modules, RequestDL can accomplish a great deal. All of this is achieved using a simplified and concise syntax.

### Installation

RequestDL can be installed using Swift Package Manager. To include it in your project, add the following dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/request-dl/request-dl-nio.git", from: "4.0.0")
]
```

### Where to start?

RequestDL is divided into two main parts: (a) ``RequestDL/Property``; and (b) ``RequestDL/RequestTask``.

#### The Property protocol

This part is related to request construction, providing various methods and objects to specify the URL, payload, and headers. The ``Property`` utilizes the opaque type `some` to allow the implementation of declarative blocks that are compiled with the help of ``RequestDL/PropertyBuilder``, an `@resultBuilder`.

```swift
@PropertyBuilder
func appleWebsite() -> some Property {
    BaseURL("apple.com")

    RequestMethod(.post)
    AcceptHeader(.json)

    Payload(verbatim: "Hello Apple!")
}
```

#### The RequestTask protocol

This protocol is part of the request result processing. Thanks to async/await, we have the possibility of receiving the data through an `AsyncSequence` as well as the `Data` containing the raw bytes. Additionally, we can use ``RequestDL/RequestTaskModifier`` and ``RequestDL/RequestTaskInterceptor`` to perform various types of operations. The request is finalized using the ``RequestDL/RequestTask/result()`` method.

```swift
try await DataTask {
    BaseURL("apple.com")
    // Other properties
}
.result()
```

### Features

- [x] [Declarative request builder](<doc:Creating-requests-from-scratch>);
- [x] [mTLS / TLS / SSL / PSK](<doc:Secure-connection>);
- [x] [JSON / Codable / Multipart / URL Encoded](<doc:Exploring-payload>);
- [x] [UploadTask / DownloadTask / DataTask / MockedTask](<doc:Exploring-task>);
- [x] [Modifiers & Interceptors](<doc:Modifiers-and-Interceptors>);
- [x] [Upload & Download progress](<doc:Upload-and-download-progress>);
- [x] [Swift Concurrency](<doc:Swift-concurrency>);
- [x] [Combine support](<doc:Exploring-combine>) (Apple platforms only);
- [x] [Image loading for SwiftUI, UIKit, AppKit and watchOS](<doc:Loading-images>) (Apple platforms only);
- [x] [Distributed tracing](<doc:Distributed-tracing>);
- [x] [Configuration-driven requests](<doc:Configuration-driven-requests>) (via swift-configuration);

We are excited to expand this list with many other features. Start by making your contribution in [Discussions](https://github.com/orgs/request-dl/discussions) or by opening a PR (Pull Request).

## Topics

### First steps

- <doc:Creating-the-project-property>
- <doc:Preparing-the-certificates>

### Essentials

- <doc:Building-the-request>
- <doc:Executing-the-request>

### Advanced

- <doc:Request-Customization>
