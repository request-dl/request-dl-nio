# Advanced Request Customization

Explore advanced techniques for customizing HTTP requests, such as accessing and modifying their underlying configuration during the build process.

## Overview

While RequestDL's high-level APIs like `FlexibleURL`, `Payload`, and `Headers` cover most common scenarios, there are cases where you need deeper control or insight into the request being built. RequestDL provides mechanisms like `PropertyReader` and `PropertyContext` that allow you to inspect and potentially modify aspects of a request based on its configuration, such as the URL, headers, or other parameters, as it is being constructed. This enables powerful customization patterns, like conditionally applying authorization tokens based on the target host.

## Accessing Configuration During Build

The `PropertyReader` and `PropertyContext` work together to provide access to the request's configuration at a specific point during the property resolution phase. This allows for dynamic adjustments or conditional logic based on the state of the request being built.

### Example: Conditional Authorization

```swift
struct ConditionalAuthModifier: PropertyModifier {
    let token: String

    func body(content: Content) -> some Property {
        PropertyReader(content) { context in 
            // Access the request configuration via the context
            if context.requestConfiguration.url.contains("api.example.com") {
                // Conditionally apply an authorization header
                Authorization(.bearer, token: token)
            }
        }
    }
}
```

In this example, the `ConditionalAuthModifier` uses `PropertyReader` to wrap another property (`content`). The `PropertyContext` passed to the closure contains the `requestConfiguration`, which includes details like the final URL. Logic can then be applied based on these details.

## Topics

### Accessing Property Context

- ``RequestDL/PropertyReader``
- ``RequestDL/PropertyContext``

### Core Concepts

- ``RequestDL/RequestConfiguration``
- ``RequestDL/RequestBody``
