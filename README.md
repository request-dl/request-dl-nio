[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Frequest-dl%2Frequest-dl%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/request-dl/request-dl)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Frequest-dl%2Frequest-dl%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/request-dl/request-dl)
[![codecov](https://codecov.io/gh/request-dl/request-dl/branch/main/graph/badge.svg?token=MW5J053T85)](https://codecov.io/gh/request-dl/request-dl)

# RequestDL

> Thanks to **Mike Lewis**, progress is seamlessly integrated into this library,
providing a simple and streamlined experience.

RequestDL is a Swift package designed to simplify the process of performing network
requests. It provides a set of tools, including the `RequestTask` protocol, which
supports different types of requests, including `DataTask`, `DownloadTask`, and 
`UploadTask`.

One of the key features of RequestDL is its support for specifying properties of a
request, such as `Query`, `Payload`, and `Headers`, among others. You can also use 
`RequestTaskModifier` and `RequestTaskInterceptor` to process the response after the request is 
complete, allowing for actions like decoding, mapping, error handling based on status
codes, and logging responses in the console.

The `Property` protocol is another powerful feature that allows developers to
implement custom properties to define various aspects of the request within a 
struct specification or using the `@PropertyBuilder`. This makes it easy to customize 
requests to meet specific needs.

## [Documentation](https://request-dl.github.io/request-dl/documentation/requestdl/)

Check out our comprehensive documentation to get all the necessary information to start using RequestDL in your project.

### Articles

- [Exploring Combine Support](Sources/RequestDL/Documentation/Articles/Combine-Support.md)
- [Creating Requests from Scratch](Sources/RequestDL/Documentation/Articles/Declarative-request-builder.md)
- [Using Modifiers and Interceptors](Sources/RequestDL/Documentation/Articles/Modifiers-&-Interceptors.md)
- [Exploring the Payload](Sources/RequestDL/Documentation/Articles/Payload-Diversity.md)
- [Adding a Secure Connection Protocol](Sources/RequestDL/Documentation/Articles/Secure-Connection.md)
- [Using Swift Concurrency from Beginning](Sources/RequestDL/Documentation/Articles/Swift-Concurrency.md)
- [Exploring the Task Diversity](Sources/RequestDL/Documentation/Articles/Task-Diversity.md)
- [Using Progress for Upload and Download Requests](Sources/RequestDL/Documentation/Articles/Upload-&-Download-progress.md)

### Translations

- [Portuguese](https://github.com/brennobemoura/requestdl-documentation)

We would be delighted to have your help in translating our documentation into your preferred language! Simply open a Pull Request on our repository with the link to your translated version. We are looking forward to receiving your contribution!

## Installation

RequestDL can be installed using Swift Package Manager. To include it in your project,
add the following dependency to your Package.swift file:

```swift
dependencies: [
    .package(url: "https://github.com/request-dl/request-dl.git", from: "2.3.0")
]
```

## Usage

Using RequestDL is easy and intuitive. You can create network requests in a 
declarative way, specifying the properties of the request through the use of 
the `Property` protocol or using the `@PropertyBuilder` attribute.

Here's an example of a simple `DataTask` that queries Google for the term "apple", 
logs the response in the console, and ignores the HTTP's response head:

```swift
try await DataTask {
    BaseURL("google.com")
    
    HeaderGroup {
        AcceptHeader(.json)
        CustomHeader(name: "xxx-api-key", value: token)
    }
    
    Query(name: "q", value: "apple")
}
.logInConsole(true)
.decode(GoogleResponse.self)
.extractPayload()
.result()
```

This code creates a `DataTask` with the `BaseURL` set to "google.com", a `HeaderGroup`
containing the "Accept" set to "application/json", a "xxx-api-key" header set the API 
token, and a query parameter with the key "q" and the value "apple". It then sets the 
`logInConsole` property to true, which will print the response in the console when
the request is completed. It also decodes the response into an instance of 
`GoogleResponse` and then ignores it.

This is just a simple example of what RequestDL can do. Check out the documentation
for more information on how to use it.

## Versioning

We follow semantic versioning for this project. The version number is composed of three parts: MAJOR.MINOR.PATCH.

- MAJOR version: Increments when there are incompatible changes and breaking changes. These changes may require updates to existing code and could potentially break backward compatibility.

- MINOR version: Increments when new features or enhancements are added in a backward-compatible manner. It may include improvements, additions, or modifications to existing functionality.

- The PATCH version includes bug fixes, patches, and safe modifications that address issues, bugs, or vulnerabilities without disrupting existing functionality. It may also include new features, but they must be implemented carefully to avoid breaking changes or compatibility issues.

It is recommended to review the release notes for each version to understand the specific changes and updates made in that particular release.

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
