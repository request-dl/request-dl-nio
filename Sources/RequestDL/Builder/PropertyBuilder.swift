//
//  PropertyBuilder.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

/**
 A custom result builder for composing a request with properties.

 You use a property builder by adding multiple properties to a request, and returning them as
 a composed property within the closure.

 Example:

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
     Query("abc", forKey: "string")
     Payload("some-content", using: .utf8)
     Path("search")
     Group {
         BaseURL("google.com")
         Query(1, forKey: "page")
     }
 }
 ```
 */
@resultBuilder
public struct PropertyBuilder {

    /**
     The buildBlock method that returns an empty `EmptyProperty`.

     Use this method when you want to return an empty `EmptyProperty` block in your
     `PropertyBuilder` implementation.
     */
    public static func buildBlock() -> EmptyProperty {
        EmptyProperty()
    }

    /// Builds a single instance of `Property` component.
    public static func buildBlock<Content: Property>(_ component: Content) -> Content {
        component
    }

    /// A helper method for the `PropertyBuilder` to include optional content in the result builder.
    public static func buildIf<Content: Property>(_ content: Content?) -> _OptionalContent<Content> {
        _OptionalContent(content)
    }

    /**
     Constructs a property builder that can build a conditional block of properties.

     - Note: This is a result builder method that is called when the builder encounters an `if` statement
     with a condition that evaluates to `true`.
     */
    public static func buildEither<
        TrueProperty: Property,
        FalseProperty: Property
    >(first: TrueProperty) -> _ConditionalContent<TrueProperty, FalseProperty> {
        _ConditionalContent(first: first)
    }

    /**
     A helper method for the `@PropertyBuilder` to build conditional content.

     Use `buildEither(first:)` to specify content when a condition is true and
     `buildEither(second:)` to specify content when it's false.

     Example:

     ```swift
     Group {
         if condition {
             Query("foo", forKey: "password")
         } else {
             Query("bar", forKey: "password")
         }
     }
     */
    public static func buildEither<
        TrueProperty: Property,
        FalseProperty: Property
    >(second: FalseProperty) -> _ConditionalContent<TrueProperty, FalseProperty> {
        _ConditionalContent(second: second)
    }

    /**
     This function is used by Swift when there is an `if #available()` statement in the code. It allows a
     property to be conditionally included in the request if the necessary API is available on the user's device.

     Here's an example of how it can be used:

     ```swift
     Group {
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

// swiftlint:disable function_parameter_count identifier_name
extension PropertyBuilder {

    public static func buildBlock<
        C0: Property,
        C1: Property
    >(
        _ c0: C0,
        _ c1: C1
    ) -> _TupleContent<(C0, C1)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> _TupleContent<(C0, C1, C2)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> _TupleContent<(C0, C1, C2, C3)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> _TupleContent<(C0, C1, C2, C3, C4)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property,
        C6: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5, C6)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
            await C6.makeProperty(c6, $0)
        }
    }

    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property,
        C3: Property,
        C4: Property,
        C5: Property,
        C6: Property,
        C7: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> _TupleContent<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        _TupleContent {
            await C0.makeProperty(c0, $0)
            await C1.makeProperty(c1, $0)
            await C2.makeProperty(c2, $0)
            await C3.makeProperty(c3, $0)
            await C4.makeProperty(c4, $0)
            await C5.makeProperty(c5, $0)
            await C6.makeProperty(c6, $0)
            await C7.makeProperty(c7, $0)
        }
    }
}
