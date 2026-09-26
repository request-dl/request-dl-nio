//
// See LICENSE for this package's licensing information.
//

/// A property that iterates over a sequence of data and produces properties for each element.
///
/// The ``PropertyForEach`` property is used to create a property for each element of a given `Data` sequence, identified
/// by its `ID`. The property to be produced is determined by the `content` closure that takes each element
/// of the sequence as input and produces a property.
///
/// ```swift
/// let paths = ["user", "search", "results"]
///
/// DataTask {
///     BaseURL("ecommerce.com")
///     PropertyForEach(paths, id: \.self) {
///         Path($0)
///     }
/// }
/// ```
public struct PropertyForEach<Data, ID, Content>: Property
where Data: Sequence & Sendable, ID: Hashable & Sendable, Content: Property {

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

    ///
    /// Creates a new instance with `Data` identified by a `keyPath`.
    ///
    /// - Parameters:
    /// - data: The sequence of data to be iterated over.
    /// - id: A `KeyPath` that identifies each element in the data sequence.
    /// - content: A closure that takes an element of the data sequence as input and produces
    /// a property for that element.
    ///
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID> & Sendable,
        @PropertyBuilder content: @escaping @Sendable (Data.Element) -> Content
    ) {
        self.data = data
        self.id = { $0[keyPath: id] }
        self.content = content
    }

    ///
    /// Creates a new instance where the elements of the data sequence are identifiable.
    ///
    /// - Parameters:
    ///    - data: The sequence of data to be iterated over.
    ///    - content: A closure that takes an element of the data sequence as input and produces a
    /// property for that element.
    ///
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

    ///
    ///  Creates a new instance for a `Range` of `Int`.
    ///
    ///  - Parameters:
    ///    - data: The `Range` of `Int` values to be iterated over.
    ///    - content: A closure that takes an `Int` value as input and produces a
    ///    property for that value.
    ///
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

    ///
    ///  Creates a new instance for a `ClosedRange` of `Int`.
    ///
    ///  - Parameters:
    ///    - data: The `ClosedRange` of `Int` values to be iterated over.
    ///    - content: A closure that takes an `Int` value as input and produces a property for that value.
    ///
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

        // One seed for this whole `PropertyForEach` -- exactly what a single ordinary
        // `@StoredObject`-holding sibling would itself consume at this same point in the tree.
        // This, not `property.pathway` alone, is what tells two sibling instances of the same
        // reusable component (each with their own internal `PropertyForEach`) apart: `pathway`
        // is purely type/id-based and collides for two structurally-identical siblings with no
        // distinguishing id anywhere, which is exactly why `SeedFactory`'s visit-order counter
        // exists in the first place (see `IdentifiedGraphValue.pathway`'s own doc comment). Drawn
        // once, before iterating, rather than once per element: that "turn" is this ForEach's
        // own place in the surrounding visit order, not a per-element concern.
        let turn = inputs.seedFactory(inputs.namespaceID)

        for element in property.data {
            let id = property.id(element)
            let content = property.content(element)

            var elementInputs = inputs
            // Scopes every `@StoredObject` this element's `content` declares to a namespace keyed
            // by `id` -- not by visit order within this iteration. See
            // `elementNamespaceID(outer:turn:id:)`'s own doc comment for why that distinction
            // matters, and why `turn`, not `property.pathway`, is folded in here.
            elementInputs.namespaceID = Self.elementNamespaceID(
                outer: inputs.namespaceID,
                turn: turn,
                id: id
            )

            let output = try await Content._makeProperty(
                property: property.detach(id: .custom(id), next: content),
                inputs: elementInputs
            )

            group.append(output.node)
        }

        return .children(group)
    }

    // MARK: - Private static methods

    /// A namespace unique to `outer` (so two `PropertyForEach`s under different explicit
    /// `@PropertyNamespace`s, or nested inside each other, can't collide even if their `turn`s and
    /// `id`s happen to coincide) crossed with `turn` (this `PropertyForEach`'s own place in the
    /// surrounding visit order, distinguishing sibling instances of the same reusable component
    /// from each other) crossed with one element's own `id`.
    ///
    /// `@StoredObject` identity is otherwise keyed by structural visit order alone (see
    /// `SeedFactory`): correct for a fixed, statically-declared sibling sequence, where "the Nth
    /// stored object visited" and "which declaration this is" coincide and stay coincident across
    /// re-resolves. Neither holds for one `PropertyForEach`'s own elements: the whole point of its
    /// `id:` parameter -- the caller's explicit, `SwiftUI.ForEach`-style stability contract -- is
    /// that the *data*, not its position within this one iteration, determines identity. Without
    /// this override, reordering, filtering, or re-fetching the same logical collection in a
    /// different order silently handed one element's cached `@StoredObject` state (a session, a
    /// token, cookies) to a different element, since the Nth element visited always drew the Nth
    /// seed regardless of which logical item it now was.
    ///
    /// `turn` is what keeps this reproducible across re-resolves of the identical tree despite
    /// being seed-derived: `SeedFactory` starts fresh every top-level resolution (see `Resolve
    /// .init`'s own doc comment), and the same structural position, visited in the same order,
    /// always draws the same sequence of seeds -- so re-resolving the identical declaration
    /// reproduces the identical `turn`, and therefore the identical per-element namespace, letting
    /// `Internals.Storage`'s process-wide cache correctly recognize it as the same element again.
    ///
    /// Scoped to exactly this `PropertyForEach`'s own elements, not adopted globally: a plain
    /// sibling sequence (no `PropertyForEach` involved) has no `id:` to honor in the first place,
    /// and still needs visit order alone to disambiguate same-type-but-different-instance siblings
    /// whose `GraphID` otherwise collides.
    private static func elementNamespaceID(
        outer: PropertyNamespace.ID,
        turn: Seed,
        id: ID
    ) -> PropertyNamespace.ID {
        .init(
            base: ForEachElementNamespaceBase.self,
            namespace: "\(outer).\(turn).\(id)"
        )
    }
}

/// Pure marker type: exists only so `PropertyForEach`'s per-element `PropertyNamespace.ID`s can
/// never collide with a namespace `@PropertyNamespace` (or any future caller of that same `init`)
/// constructs for an unrelated reason, regardless of what string either happens to build.
private enum ForEachElementNamespaceBase {}
