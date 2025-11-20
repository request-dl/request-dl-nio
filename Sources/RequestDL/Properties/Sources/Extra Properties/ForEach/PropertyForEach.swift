/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property that iterates over a sequence of data and produces properties for each element.

 The ``PropertyForEach`` property is used to create a property for each element of a given `Data` sequence, identified
 by its `ID`. The property to be produced is determined by the `content` closure that takes each element
 of the sequence as input and produces a property.

 ```swift
 let paths = ["user", "search", "results"]

 DataTask {
     BaseURL("ecommerce.com")
     PropertyForEach(paths, id: \.self) {
         Path($0)
     }
 }
 ```
 */
public struct PropertyForEach<Data, ID, Content>: Property where Data: Sequence & Sendable, ID: Hashable & Sendable, Content: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// The sequence of data to be iterated over.
    public let data: Data

    /// A closure that takes an element of the data sequence as input and produces a property
    /// for that element.
    public let content: @Sendable (Data.Element) -> Content

    // MARK: - Private properties

    private let id: @Sendable (Data.Element) -> ID

    /**
     Creates a new instance with `Data` identified by a `keyPath`.

     - Parameters:
     - data: The sequence of data to be iterated over.
     - id: A `KeyPath` that identifies each element in the data sequence.
     - content: A closure that takes an element of the data sequence as input and produces
     a property for that element.
     */
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID> & Sendable,
        @PropertyBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) {
        self.data = data
        self.id = { $0[keyPath: id] }
        self.content = content
    }

    /**
     Creates a new instance where the elements of the data sequence are identifiable.

     - Parameters:
        - data: The sequence of data to be iterated over.
        - content: A closure that takes an element of the data sequence as input and produces a
     property for that element.
     */
    public init(
        _ data: Data,
        @PropertyBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.init(
            data,
            id: \.id,
            content: content
        )
    }

    /**
      Creates a new instance for a `Range` of `Int`.

      - Parameters:
        - data: The `Range` of `Int` values to be iterated over.
        - content: A closure that takes an `Int` value as input and produces a
        property for that value.
     */
    public init<Bound>(
        _ data: Data,
        @PropertyBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) where Bound: Comparable & Hashable, Data == Range<Bound>, ID == Int {
        self.init(
            data,
            id: \.hashValue,
            content: content
        )
    }

    /**
      Creates a new instance for a `ClosedRange` of `Int`.

      - Parameters:
        - data: The `ClosedRange` of `Int` values to be iterated over.
        - content: A closure that takes an `Int` value as input and produces a property for that value.
     */
    public init<Bound>(
        _ data: Data,
        @PropertyBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) where Bound: Comparable & Hashable, Data == ClosedRange<Bound>, ID == Int {
        self.init(
            data,
            id: \.hashValue,
            content: content
        )
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PropertyForEach<Data, ID, Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var group = ChildrenNode()

        for element in property.data {
            let id = property.id(element)
            let content = property.content(element)

            let output = try await Content._makeProperty(
                property: property.detach(id: .custom(id), next: content),
                inputs: inputs
            )

            group.append(output.node)
        }

        return .children(group)
    }
}
