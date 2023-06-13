# Creating requests from scratch

Discover the various available types that can be used to specify a request. 

## Overview

RequestDL is a powerful Swift library designed according to the declarative programming paradigm, offering an extensive API for specifying the fields of a request. Whether it's an HTTP request or any other network operation, RequestDL simplifies the process by focusing on four key fields:

1. **URL**: Specify the target URL for your request, allowing you to connect to the desired endpoint.
2. **Method**: Define the HTTP method (GET, POST, PUT, DELETE, etc.) to determine the action to be performed on the server.
3. **Headers**: Add custom headers to your request, such as authentication tokens, content types, or any other metadata required for proper communication.
4. **Body**: Include the payload or data to be sent as part of your request, enabling you to transmit information or perform operations on the server.

With RequestDL's intuitive syntax and comprehensive API, you can effortlessly construct and send requests, making API interactions in your Swift projects more concise and declarative. Enjoy a streamlined approach to handling requests while focusing on the essential aspects of your application's networking needs.

## URL

This section details how to specify the request URL using the available declarative objects.

### BaseURL

The ``RequestDL/BaseURL`` is the entry point as it specifies the scheme and host to be queried during the request. To start using it, it is important to pay attention to some rules:

- Scheme must be of type ``RequestDL/URLScheme``.
- Host is a string without scheme.

Here's an example of usage:

```swift
// Always HTTPS
BaseURL("apple.com")

// Specifying the scheme
BaseURL(.http, host: "apple.com")
```

- Note: Successively specifying the `BaseURL` within a declarative block will override the previously specified value.

- Warning: It is extremely important to specify the BaseURL in each request. Otherwise, RequestDL may throw an error.

### Path

The ``RequestDL/Path`` is used to specify the URL path to reach the endpoint of the request. You can specify as many paths as necessary and even mix different types such as Int, Double, or any other type that conforms to `LosslessStringConvertible`.

Here's an example with a single specified path:

```swift
// base-url/api/v1
Path("api/v1")
```

Here's an example with multiple specified paths, combined in the final URL:

```swift
// base-url/api/v1/users/18900
Path("api/v1")
Path("users")
Path(18900)
```

By using the `Path` component, you can easily construct the desired URL path for your request in RequestDL.

### Query

## Method

## Headers

### CustomHeader

### AcceptHeader

### CacheHeader

### HostHeader

### OriginHeader

### RefererHeader

### Authorization

## Body

### Payload

### Form

## Base objects 

### Property

### EmptyProperty

### AsyncProperty

### PropertyModifier

### PropertyBuilder

## Group

### PropertyForEach

### Group

### QueryGroup

### HeaderGroup

### FormGroup

## Other cool stuff

### Session

### SecureConnection

### ReadingMode

---

## See also

- [Caching your responses](<doc:Cache-support>);
- [Storing and reading values inside properties](<doc:Property-state>);
