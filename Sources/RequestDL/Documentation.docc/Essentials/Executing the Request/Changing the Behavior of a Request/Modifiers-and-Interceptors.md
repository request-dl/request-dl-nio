# Using Modifiers and Interceptors

Discover how to implement a modifier and interceptor to handle and make your requests self-sufficient.

## Overview

Each queried endpoint is subject to different handling rules. In most cases, the flow of receiving the response and delivering the processed data is the same.

To integrate the request processing logic directly into the construction of a ``RequestDL/RequestTask``, two protocols are provided: ``RequestDL/RequestTaskModifier`` and ``RequestDL/RequestTaskInterceptor``.

### Task Modifier

There are infinite possibilities when implementing a `Modifier`. It is possible to perform operations both before making a request and after receiving the response.

When implementing your `Modifier`, simply call the ``RequestDL/RequestTask/modifier(_:)`` method, and your request will be handled by it. Additionally, you can specify the `Input` and `Output` of the `Modifier` to implement specific logic.

Some interesting ideas for API-specific `Modifier`:

1. Token Refresh

    ```swift
    struct TokenRefreshModifier: RequestTaskModifier {

        typealias Input = TaskResult<Data>

        func body(_ task: Content) async throws -> Input {
            let result = try await task.result()
        
            guard result.head.status.code == 401 else {
                return result
            }
            
            // If no error is thrown, then it's safe to re-run the request
            try await refreshToken()
            return try await task.result()
        }
    }
    ```

2. Project defaults modifiers

    ```swift
    struct DefaultsModifier<Object: Decodable>: RequestTaskModifier {

        typelias Input = TaskResult<Data>

        let objectType: Object.Type

        func body(_ task: Content) async throws -> Object {
            try await task
                .onStatusCode(.internalServerError) {
                    throw InternalServerError()
                }
                .refreshToken()
                .keyPath(\.result)
                .decode(objectType)
                .extractPayload()
                .result()
        }
    }
    ```

> Note: RequestDL provides a variety of implemented modifiers, which can be checked through the ``RequestDL/Modifiers`` enumerator.

### Task Interceptor

The `Interceptor` aims to perform an operation independently of the rest of the request. It functions as a code diversion that is always executed regardless of the conditions.

When implementing your `Interceptor`, you should call the method ``RequestDL/RequestTask/interceptor(_:)`` to incorporate it into any request. Every `Interceptor` must specify the type of the `Element`, which is the result object of the original intercepted ``RequestTask``.

Here is a simple example of how to implement an `Interceptor`:

```swift
struct AlwaysPrintInterceptor<Element>: RequestTaskInterceptor {

    func output(_ result: Result<Element, Error>) {
        switch result {
        case .success(let element):
            print("[Success]", element)
        case .failure(let error):
            print("[Failure]", error)
        }
    }
}
```

> Note: RequestDL provides some interceptors, which can be checked through the ``RequestDL/Interceptors`` enumerator.

## Topics

### Modifying the request

- ``RequestDL/RequestTaskModifier``
- ``RequestDL/ModifiedRequestTask``
- ``RequestDL/RequestTask/modifier(_:)``

### Intercepting the request

- ``RequestDL/RequestTaskInterceptor``
- ``RequestDL/InterceptedRequestTask``
- ``RequestDL/RequestTask/interceptor(_:)``

### Exploring the available modifiers

- ``RequestDL/Modifiers``

### Exploring the available interceptors

- ``RequestDL/Interceptors`` 
