[![Swift](https://img.shields.io/badge/Swift-5.7-blue.svg)](https://swift.org)
[![MIT](https://img.shields.io/badge/License-MIT-red.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/request-dl/request-dl/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/request-dl/request-dl/actions/workflows/tests.yml)
[![Test Coverage](https://api.codeclimate.com/v1/badges/516f7228a532b73b5540/test_coverage)](https://codeclimate.com/github/brennobemoura/request-dl/test_coverage)

# RequestDL

RequestDL is a Swift package designed to simplify the process of performing network
requests. It provides a set of tools, including the Task protocol, which supports
different types of requests, including DataTask, DownloadTask, and BytesTask.

One of the key features of RequestDL is its support for specifying properties of a
URLRequest, such as Query, Payload, and Headers, among others. You can also use 
TaskModifier and TaskInterceptor to process the response after the request is 
complete, allowing for actions like decoding, mapping, error handling based on status
codes, and logging responses in the console.

RequestDL's Property protocol is another powerful feature that allows developers to
implement custom properties to define various aspects of the URLRequest within a 
struct specification or using the @PropertyBuilder. This makes it easy to customize 
requests to meet specific needs.

- **[Documentation](https://brennobemoura.github.io/request-dl/documentation/requestdl/)**

## Installation

RequestDL can be installed using Swift Package Manager. To include it in your project,
add the following dependency to your Package.swift file:

```swift
dependencies: [
    .package(url: "https://github.com/username/RequestDL.git", from: "1.0.0")
]
```

## Usage

Using RequestDL is easy and intuitive. You can create network requests in a 
declarative way, specifying the properties of the request through the use of 
the Property protocol or using the @PropertyBuilder attribute.

Here's an example of a simple DataTask that queries Google for the term "apple", 
logs the response in the console, and ignores the URLResponse:

```swift
try await DataTask {
    BaseURL("google.com")
    
    HeaderGroup {
        Headers.Accept(.json)
        Headers.ContentType(.json)
    }
    
    Query("apple", forKey: "q")
}
.logInConsole(true)
.decode(GoogleResponse.self)
.ignoreResponse()
.response()
```

This code creates a `DataTask` with the `BaseURL` set to "google.com", a `HeaderGroup`
containing the "Accept" and "Content-Type" headers set to "application/json", and 
a query parameter with the key "q" and the value "apple". It then sets the 
`logInConsole` property to true, which will print the response in the console when
the request is completed. It also decodes the response into an instance of 
`GoogleResponse` and then ignores it.

This is just a simple example of what RequestDL can do. Check out the documentation
for more information on how to use it.

## Contributing

If you find a bug or have an idea for a new feature, please open an issue or 
submit a pull request. We welcome contributions from the community!

## Acknowledgments

This library owes a lot to the work of Carson Katri and his Swift package 
[Request](https://github.com/carson-katri/swift-request). Many of the core 
concepts and techniques used in RequestDL were inspired by Carson's library, and 
the original implementation of RequestDL even used a fork of Carson's library as
its foundation. 

Without Carson's work, this library would not exist in its current form. Thank you, 
Carson, for your contributions to the Swift community and for inspiring the development 
of RequestDL.
