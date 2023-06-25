# Creating requests from scratch

Discover the various available types that can be used to specify a request. 

## Overview

When using RequestDL, it is crucial to understand the fundamental concepts that define the components of an HTTP request as they play a crucial role in how requests are made.

Requests are built by combining different essential components: URL, method, headers, and body. Each of these components is represented by an extensive set of objects that allow you to configure and customize every aspect of a request.

This flexible and modular approach of RequestDL provides granular control over the requests and allows you to adapt them according to the specific needs of each scenario.

### URL

The URL of a request consists of four main parts: scheme, host, paths, and query parameters. There are several objects available in RequestDL that facilitate working with each of these components.

- **[BaseURL](<doc:RequestDL/BaseURL>)**

    Defines the scheme and host of the URL. It allows you to specify whether the request will use HTTP or HTTPS as the scheme, as well as the destination host.

    ```swift
    BaseURL(.http, host: "apple.com")
    ```

- **[Path](<doc:RequestDL/Path>)**

    Adds paths to the URL. It enables you to include specific path segments in the URL, providing a hierarchical structure for locating the desired resources.

    ```swift
    Path("api/v1")
    ```

- **[Query](<doc:RequestDL/Query>)**

    Adds query parameters to the URL. These parameters are used to convey additional information in the request.

    ```swift
    Query(name: "create_at", value: Date())
    ```

> Tip: Explore the ``RequestDL/URLEncoder`` to use other ways of inserting parameters in the URL.

### Method

HTTP requests have a series of methods to perform different operations on the same endpoint. The most common methods are GET, POST, PUT, and DELETE, each with its own meaning.

- **[RequestMethod](<doc:RequestDL/RequestMethod>)**

    Specifies the method to be used in the request. The values are predefined by the ``RequestDL/HTTPMethod`` object. The default method is always GET.

    ```swift
    RequestMethod(.post)
    ```

> Note: Check out the [HTTP request methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods) to learn more.

### Headers

The headers of an HTTP request play a fundamental role in establishing settings and conveying relevant information between the client and the server.

They are responsible for defining various characteristics of the transmitted object and indicating the client's expectations regarding the response.

Additionally, headers can include API access keys, authentication details, accepted or expected content types, location information, and many other important details.

- **[CustomHeader](<doc:RequestDL/CustomHeader>)**

    Specifies a header with a custom name and value. Recommended for use when there is no specific header object defined by RequestDL.

    ```swift
    CustomHeader(name: "X-api-token", value: "*****")
    ```

- **[AcceptHeader](<doc:RequestDL/AcceptHeader>)**

    Defines the expected data type as the response from the client. Predefined values in ``RequestDL/ContentType``.

    ```swift
    AcceptHeader(.json)
    ```

Learn more in [Meet the headers](#meet-the-headers).

### Body

The most essential and critical part of an HTTP request is the body. It is essential for sending various types of data to the server. It is critical as it requires various optimization, monitoring, compression, integrity, and security resources.

- **[Payload](<doc:RequestDL/Payload>)**

    Defines the request body in the raw byte format. The understanding of the sent data is defined by the ``RequestDL/ContentType`` with predefined values.

    ```swift
    Payload(verbatim: "Hello World!", contentType: .text)
    ```

- **[Form](<doc:RequestDL/Form>)**

    Defines a part of the request body in the **multipart/form-data** format. To define the entire set, check out the ``RequestDL/FormGroup``.

    ```swift
    Form(
        name: "hello_world",
        contentType: .text,
        verbatim: "Hello World!"
    )
    ```

    > Important: The **name** parameter is required, while the **filename** is optional.

Explore more about the request body in [Exploring the payload](<doc:Exploring-payload>).

### Create your own

The Swift `@resultBuilder` combined with the opaque type makes it more flexible to develop solutions, especially respecting the unique needs of each problem.

Declarative programming has a series of advantages and disadvantages, and each solution should explore the available tools.

With ``RequestDL/Property`` and ``RequestDL/PropertyBuilder``, you can define a unique property that configures a series of behaviors within the request, which can be reused in all scenarios.

```swift
struct AppleAPI: Property {

    var body: some Property {
        // Body specification
    }
}
```

You can explore this approach to create unique solutions for any component within the request, whether it's defining the URL, headers, or body, as well as other properties related to request configuration.

Learn more in:

- **<doc:Creating-the-project-property>**
- **<doc:Secure-connection>**
- **<doc:Cache-support>**

## Topics

### The core of all requests

- ``RequestDL/Property``
- ``RequestDL/PropertyBuilder``

### The power of result builder

- ``RequestDL/PropertyGroup``
- ``RequestDL/PropertyForEach``
- ``RequestDL/EmptyProperty``
- ``RequestDL/AnyProperty``
- ``RequestDL/AsyncProperty``

### Specifying the URL

- ``RequestDL/BaseURL``
- ``RequestDL/URLScheme``
- ``RequestDL/InternetProtocol``
- ``RequestDL/BaseURLError``
- ``RequestDL/Path``

### Adding query parameters

- ``RequestDL/Query``
- ``RequestDL/QueryGroup``

### Defining the request method

- ``RequestDL/RequestMethod``
- ``RequestDL/HTTPMethod``

### Working with authentication

- ``RequestDL/Authorization``

### Meet the headers

- ``RequestDL/CustomHeader``
- ``RequestDL/AcceptHeader``
- ``RequestDL/HostHeader``
- ``RequestDL/OriginHeader``
- ``RequestDL/RefererHeader``
- ``RequestDL/CacheHeader``
- ``RequestDL/AcceptCharsetHeader``
- ``RequestDL/UserAgentHeader``
- ``RequestDL/HeaderGroup``

### Changing the headers behavior

- ``RequestDL/HeaderStrategy``
- ``RequestDL/Property/headerStrategy(_:)``

### Working with payload

- <doc:Exploring-payload>

### Making secure requests

- <doc:Secure-connection>

### Configuration of Session

- ``RequestDL/Session``

### Adding request timeout

- ``RequestDL/Timeout``
- ``RequestDL/UnitTime``

### Modifying the properties

- ``RequestDL/PropertyModifier``
- ``RequestDL/Property/modifier(_:)``
