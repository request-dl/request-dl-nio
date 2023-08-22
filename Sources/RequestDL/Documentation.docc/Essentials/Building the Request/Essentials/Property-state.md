# Storing and reading values inside properties

Discover how to obtain values and utilize classes within a property during the specification of a request.

## Overview

The integration of various important resources in a request was made possible due to the implementation of some `@propertyWrapper` that are directly linked to ``RequestDL/Property``.

### Environment

``RequestDL/PropertyEnvironment`` allows you to obtain the value of a property from ``RequestDL/PropertyEnvironmentValues`` during the construction of a property.

Internally, some objects in RequestDL use the environment to retrieve important objects that influence the request's outcome. Therefore, you can explore these resources to create your own tools aligned with your system's requirements.

You can start by specifying a ``RequestDL/PropertyEnvironmentKey`` as follows:

```swift
struct PayloadKey: PropertyEnvironmentKey {
    public static let defaultValue: Data?
}

extension PropertyEnvironmentValues {

    var payload: Data? {
        get { self[PayloadKey.self] }
        set { self[PayloadKey.self] = newValue }
    }
}

extension Property {

    func payload(_ data: Data) -> some Property {
        environment(\.payload, data)
    }
}
```

And then retrieve the value using ``RequestDL/PropertyEnvironment``:

```swift
struct GithubAPI: Property {

    @PropertyEnvironment(\.payload) var payload

    var body: some Property {
        // Other property specifications
        if let payload {
            Payload(data: payload, contentType: customGithubJSONType)
        }
    }
}
```

### StoredObject

``RequestDL/StoredObject`` stores the instantiated object in memory to assist in various optimizations.

Its main use case is in the implementation of ``RequestDL/SecureConnection``, which, in some cases, requires encoding an object to be used during TLS verification.

Its usage is simple and intuitive:

```swift
struct GithubAPI: Property {

    @StoredObject var psk = GithubSSLPSKIdentity()

    var body: some Property {
        // Other property specifications
        SecureConnection {
            PSKIdentity(psk)
        }
    }
}
```

> Note: There is a lifetime that maintains the object reference for a certain duration. After the expiration, a new object is used.

### Namespace

``RequestDL/PropertyNamespace`` directly influences the runtime memory reference where the state objects of ``RequestDL/Property`` are stored.

Due to a series of optimizations related to the functioning of SwiftNIO and AsyncHTTPClient, defining a Namespace helps RequestDL determine whether it needs to create new objects from scratch or use those that are cached in memory.

> Warning: The memory cache referred to here is related to Swift objects and not request caching.

For each `@PropertyNamespace` defined, RequestDL combines the values to form a unique memory identifier. **It is crucial to use them when working with ``RequestDL/StoredObject``**.

## Topics

### Meet the environment

- ``RequestDL/PropertyEnvironmentKey``
- ``RequestDL/PropertyEnvironmentValues``
- ``RequestDL/PropertyEnvironment``
- ``RequestDL/Property/environment(_:_:)``

### Keep objects in memory

- ``RequestDL/StoredObject``
- ``RequestDL/DynamicValue``

### Power requests with namespace

- ``RequestDL/PropertyNamespace``
