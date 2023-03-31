/*
 See LICENSE for this package's licensing information.
*/

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
    public static func buildPartialBlock<Content: Property>(first: Content) -> Content {
        first
    }

    public static func buildPartialBlock<Accumulated: Property, Next: Property>(
        accumulated: Accumulated,
        next: Next
    ) -> _PartialContent<Accumulated, Next> {
        _PartialContent(
            accumulated: accumulated,
            next: next
        )
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
    public static func buildEither<First: Property, Second: Property>(
        first component: First
    ) -> _EitherContent<First, Second> {
        .init(first: component)
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

extension PropertyBuilder {

    /// Builds a single instance of `Property` component.
    @available(*, deprecated, renamed: "buildPartialBlock(first:)")
    public static func buildBlock<Content: Property>(_ component: Content) -> Content {
        component
    }
}

// swiftlint:disable function_parameter_count identifier_name
extension PropertyBuilder {

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
    public static func buildBlock<
        C0: Property,
        C1: Property
    >(
        _ c0: C0,
        _ c1: C1
    ) -> _TupleContent<(C0, C1)> {
        _TupleContent((c0, c1)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
    public static func buildBlock<
        C0: Property,
        C1: Property,
        C2: Property
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> _TupleContent<(C0, C1, C2)> {
        _TupleContent((c0, c1, c2)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
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
        _TupleContent((c0, c1, c2, c3)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            let input3 = inputs[type, \.value.3]
            let output3 = try await C3._makeProperty(
                property: property.dynamic(\.value.3),
                inputs: input3
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            children.append(output3.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
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
        _TupleContent((c0, c1, c2, c3, c4)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            let input3 = inputs[type, \.value.3]
            let output3 = try await C3._makeProperty(
                property: property.dynamic(\.value.3),
                inputs: input3
            )

            let input4 = inputs[type, \.value.4]
            let output4 = try await C4._makeProperty(
                property: property.dynamic(\.value.4),
                inputs: input4
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            children.append(output3.node)
            children.append(output4.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
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
        _TupleContent((c0, c1, c2, c3, c4, c5)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            let input3 = inputs[type, \.value.3]
            let output3 = try await C3._makeProperty(
                property: property.dynamic(\.value.3),
                inputs: input3
            )

            let input4 = inputs[type, \.value.4]
            let output4 = try await C4._makeProperty(
                property: property.dynamic(\.value.4),
                inputs: input4
            )

            let input5 = inputs[type, \.value.5]
            let output5 = try await C5._makeProperty(
                property: property.dynamic(\.value.5),
                inputs: input5
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            children.append(output3.node)
            children.append(output4.node)
            children.append(output5.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
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
        _TupleContent((c0, c1, c2, c3, c4, c5, c6)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            let input3 = inputs[type, \.value.3]
            let output3 = try await C3._makeProperty(
                property: property.dynamic(\.value.3),
                inputs: input3
            )

            let input4 = inputs[type, \.value.4]
            let output4 = try await C4._makeProperty(
                property: property.dynamic(\.value.4),
                inputs: input4
            )

            let input5 = inputs[type, \.value.5]
            let output5 = try await C5._makeProperty(
                property: property.dynamic(\.value.5),
                inputs: input5
            )

            let input6 = inputs[type, \.value.6]
            let output6 = try await C6._makeProperty(
                property: property.dynamic(\.value.6),
                inputs: input6
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            children.append(output3.node)
            children.append(output4.node)
            children.append(output5.node)
            children.append(output6.node)
            return .init(children)
        }
    }

    @available(*, deprecated, renamed: "buildPartialBlock(accumulated:next:)")
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
        _TupleContent((c0, c1, c2, c3, c4, c5, c6, c7)) { property, inputs, type in
            let input0 = inputs[type, \.value.0]
            let output0 = try await C0._makeProperty(
                property: property.dynamic(\.value.0),
                inputs: input0
            )

            let input1 = inputs[type, \.value.1]
            let output1 = try await C1._makeProperty(
                property: property.dynamic(\.value.1),
                inputs: input1
            )

            let input2 = inputs[type, \.value.2]
            let output2 = try await C2._makeProperty(
                property: property.dynamic(\.value.2),
                inputs: input2
            )

            let input3 = inputs[type, \.value.3]
            let output3 = try await C3._makeProperty(
                property: property.dynamic(\.value.3),
                inputs: input3
            )

            let input4 = inputs[type, \.value.4]
            let output4 = try await C4._makeProperty(
                property: property.dynamic(\.value.4),
                inputs: input4
            )

            let input5 = inputs[type, \.value.5]
            let output5 = try await C5._makeProperty(
                property: property.dynamic(\.value.5),
                inputs: input5
            )

            let input6 = inputs[type, \.value.6]
            let output6 = try await C6._makeProperty(
                property: property.dynamic(\.value.6),
                inputs: input6
            )

            let input7 = inputs[type, \.value.7]
            let output7 = try await C7._makeProperty(
                property: property.dynamic(\.value.7),
                inputs: input7
            )

            var children = ChildrenNode()
            children.append(output0.node)
            children.append(output1.node)
            children.append(output2.node)
            children.append(output3.node)
            children.append(output4.node)
            children.append(output5.node)
            children.append(output6.node)
            children.append(output7.node)
            return .init(children)
        }
    }
}
