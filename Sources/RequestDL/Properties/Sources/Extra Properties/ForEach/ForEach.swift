/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property that iterates over a sequence of data and produces properties for each element.

 The `ForEach` property is used to create a property for each element of a given `Data` sequence, identified
 by its `ID`. The property to be produced is determined by the `content` closure that takes each element
 of the sequence as input and produces a property.

 Example:

 ```swift
 let paths = ["user", "search", "results"]

 DataTask {
     BaseURL("ecommerce.com")
     ForEach(paths, id: \.self) {
         Path($0)
     }
 }
 ```
 */
public struct ForEach<Data, ID, Content>: Property where Data: Sequence, ID: Hashable, Content: Property {

    /// The sequence of data to be iterated over.
    public let data: Data

    /// A closure that takes an element of the data sequence as input and produces a property
    /// for that element.
    public let content: (Data.Element) -> Content

    private let id: KeyPath<Data.Element, ID>

    private var abstractContent: Content {
        Internals.Log.failure(
            """
            There was an attempt to access a variable for which access was not expected.
            """
        )
    }

    /**
     Creates a new instance of `ForEach`.

     - Parameters:
     - data: The sequence of data to be iterated over.
     - id: A `KeyPath` that identifies each element in the data sequence.
     - content: A closure that takes an element of the data sequence as input and produces
     a property for that element.
     */
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @PropertyBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    /**
     Creates a new instance of `ForEach` where the elements of the data sequence are identifiable.

     - Parameters:
     - data: The sequence of data to be iterated over.
     - content: A closure that takes an element of the data sequence as input and produces a
     property for that element.
     */
    public init(
        _ data: Data,
        @PropertyBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.init(
            data,
            id: \.id,
            content: content
        )
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension ForEach {

    /**
      Creates a new instance of `ForEach` for a `Range` of `Int`.

      - Parameters:
        - data: The `Range` of `Int` values to be iterated over.
        - content: A closure that takes an `Int` value as input and produces a
        property for that value.
     */
    public init<Bound>(
        _ data: Data,
        @PropertyBuilder content: @escaping (Data.Element) -> Content
    ) where Bound: Comparable & Hashable, Data == Range<Bound>, ID == Int {
        self.init(
            data,
            id: \.hashValue,
            content: content
        )
    }

    /**
      Creates a new instance of `ForEach` for a `ClosedRange` of `Int`.

      - Parameters:
        - data: The `ClosedRange` of `Int` values to be iterated over.
        - content: A closure that takes an `Int` value as input and produces a property for that value.
     */
    public init<Bound>(
        _ data: Data,
        @PropertyBuilder content: @escaping (Data.Element) -> Content
    ) where Bound: Comparable & Hashable, Data == ClosedRange<Bound>, ID == Int {
        self.init(
            data,
            id: \.hashValue,
            content: content
        )
    }
}

extension ForEach {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<ForEach<Data, ID, Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        var group = ChildrenNode()

        for element in property.data {
            let output = try await Content._makeProperty(
                property: property.dynamic {
                    $0.content(element)
                },
                inputs: inputs[self, element[keyPath: property.id], \.abstractContent]
            )

            group.append(output.node)
        }

        return .init(group)
    }
}
