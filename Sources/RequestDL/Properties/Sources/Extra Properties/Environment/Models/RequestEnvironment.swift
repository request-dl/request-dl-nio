//
// See LICENSE for this package's licensing information.
//

/// A property wrapper that provides access to values stored in ``RequestEnvironmentValues``.
///
/// ## Overview
///
/// ``RequestEnvironment`` reads a value out of the ``RequestEnvironmentValues`` in scope for
/// whichever type declares it -- a ``Property`` (populated while the request's property graph is
/// built) or a ``RequestTask`` (populated the same way, when the task actually runs). Both are
/// driven by the same mechanism: reflection over the declaring type's stored properties, so no
/// extra plumbing is needed on either side beyond declaring the wrapper.
///
/// ### Usage
///
/// Declare it with a key path to the value you want:
///
/// ```swift
/// @RequestEnvironment(\.contentType) var contentType: ContentType
/// ```
///
/// In a ``Property``:
///
/// ```swift
/// struct DefaultHeader: Property {
///
///     @RequestEnvironment(\.contentType) var contentType: ContentType
///
///     var body: some Property {
///         Headers.ContentType(contentType)
///     }
/// }
/// ```
///
/// In a ``RequestTask``:
///
/// ```swift
/// struct NumberTask: RequestTask {
///
///     @RequestEnvironment(\.number) var number
///
///     func result() async throws -> Int {
///         number
///     }
/// }
/// ```
///
/// Configure the value with `.environment(_:_:)`, available on both ``Property`` and
/// ``RequestTask``:
///
/// ```swift
/// let value = try await NumberTask()
///     .environment(\.number, 2)
///     .result()
/// ```
///
/// - Note: Falls back to the key's own default when read before anything ever populated it --
/// a property never resolved through a graph, a task run via a bare `.result()`, a preview, or a
/// test reading the wrapper directly.
@propertyWrapper
public struct RequestEnvironment<Value: Sendable>: DynamicValue {

    // MARK: - Public properties

    /// The wrapped value, read out of the enclosing ``Property``/``RequestTask``'s environment.
    ///
    /// Read on demand rather than captured at init, so only the rare unpopulated path pays for
    /// the default lookup.
    public var wrappedValue: Value {
        value ?? RequestEnvironmentValues()[keyPath: keyPath]
    }

    // MARK: - Private properties

    @_Container private var value: Value?

    // Kept as the key path itself rather than as a closure reading it. The failure below
    // reports this to say which environment key was never populated, and a closure describes
    // itself as a function, which named nothing. It also drops a closure allocation per wrapper.
    private let keyPath: KeyPath<RequestEnvironmentValues, Value> & Sendable

    // MARK: - Inits

    ///
    /// Initializes a new instance of the ``RequestEnvironment`` property wrapper.
    ///
    /// - Parameter keyPath: The key path that points to the value in the ``RequestEnvironmentValues`` object.
    ///
    public init(_ keyPath: KeyPath<RequestEnvironmentValues, Value> & Sendable) {
        self.keyPath = keyPath
    }
}

// MARK: - DynamicEnvironment

extension RequestEnvironment: DynamicEnvironment {

    func update(_ values: RequestEnvironmentValues) {
        value = values[keyPath: keyPath]
    }
}

// MARK: - Deprecated aliases

@available(*, deprecated, renamed: "RequestEnvironment")
public typealias PropertyEnvironment<Value: Sendable> = RequestEnvironment<Value>

@available(*, deprecated, renamed: "RequestEnvironment")
public typealias TaskEnvironment<Value: Sendable> = RequestEnvironment<Value>
