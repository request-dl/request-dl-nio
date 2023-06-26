/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A custom result builder for composing a request with properties.

 You use a property builder by adding multiple properties to a request, and returning them as
 a composed property within the closure.

 ```swift
 func myProperties<Content: Property>(
     @PropertyBuilder content: () -> Content
 ) -> some Property {
     content()
 }
 ```

 Which will behavior as:

 ```swift
 myProperties {
     Query(name: "string", value: "abc")
     Payload("some-content", using: .utf8)
     Path("search")
     PropertyGroup {
         BaseURL("google.com")
         Query(name: "page", value: 1)
     }
 }
 ```
 */
@resultBuilder
public struct PropertyBuilder: Sendable {

    /**
     The buildBlock method that returns an empty `EmptyProperty`.

     Use this method when you want to return an empty `EmptyProperty` block in your
     `PropertyBuilder` implementation.
     */
    public static func buildBlock() -> EmptyProperty {
        EmptyProperty()
    }

    /// Builds a single instance of `Property` component.
    public static func buildPartialBlock<Content: Property>(first: Content) -> Content {
        first
    }

    /// Returns a partial result for a block of properties in a `@PropertyBuilder` function.
    ///
    /// This function is called by the Swift compiler to accumulate properties within a `@PropertyBuilder`
    /// function. It takes two parameters: the accumulated properties so far, and the next property to add
    /// to the list. It then returns a partial result that includes both the accumulated properties and the
    /// next property.
    ///
    /// - Parameters:
    ///    - accumulated: The properties accumulated so far.
    ///    - next: The next property to add to the list.
    ///
    /// - Returns: A partial result that includes both the accumulated properties and the next property.
    public static func buildPartialBlock<Content: Property, Next: Property>(
        accumulated: Content,
        next: Next
    ) -> _PartialContent<Content, Next> {
        .init(accumulated: accumulated, next: next)
    }

    /// A helper method for the `PropertyBuilder` to include optional content in the result builder.
    public static func buildIf<Content: Property>(_ content: Content?) -> _OptionalContent<Content> {
        _OptionalContent(content)
    }

    /**
     Constructs a property builder that can build a conditional block of properties.

     > Note: This is a result builder method that is called when the builder encounters an `if` statement
     with a condition that evaluates to `true`.
     */
    public static func buildEither<First: Property, Second: Property>(
        first component: First
    ) -> _EitherContent<First, Second> {
        .init(first: component)
    }

    /**
     A helper method for the `@PropertyBuilder` to build conditional content.

     Use `buildEither(first:)` to specify content when a condition is true and
     `buildEither(second:)` to specify content when it's false.

     ```swift
     PropertyGroup {
         if condition {
             Query(name: "password", value: "foo")
         } else {
             Query(name: "password", value: "bar")
         }
     }
     */
    public static func buildEither<First: Property, Second: Property>(
        second component: Second
    ) -> _EitherContent<First, Second> {
        .init(second: component)
    }

    /**
     This function is used by Swift when there is an `if #available()` statement in the code. It allows a
     property to be conditionally included in the request if the necessary API is available on the user's device.

     Here's an example of how it can be used:

     ```swift
     PropertyGroup {
         if #available(iOS 15, *) {
             Headers(...)
         }
     }
     ```

     In this example, the `Header` property will only be included if the user's device is running iOS 15 or later.
     If the device is running an older version of iOS, the `Header` property will be excluded from the request.
     */
    public static func buildLimitedAvailability<Content: Property>(_ component: Content) -> Content {
        component
    }
}
