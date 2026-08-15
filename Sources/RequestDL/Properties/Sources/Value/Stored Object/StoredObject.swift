//
// See LICENSE for this package's licensing information.
//

/// A property wrapper that defines a stored object inside `Property` objects.
///
/// This wrapper can be used to store any **class** inside the property declaration.
///
/// ```swift
/// struct MyProperty: Property {
///
///    @StoredObject var myObject = MyClass()
///
///    var body: some Property {
///        ...
///    }
/// }
/// ```
///
/// In this example, an instance of `MyClass` will be stored in memory so that the `myObject` property
/// can always refer to the same instance. However, there are certain conditions that may cause the
/// reference to expire, leading to the replacement of the instance with a new one.
@propertyWrapper
public struct StoredObject<Object: AnyObject & Sendable>: DynamicValue {

    private struct Key: Sendable, Hashable {

        let configuration: StoredObjectConfiguration

        func hash(into hasher: inout Hasher) {
            hasher.combine(configuration)
            hasher.combine(ObjectIdentifier(Object.self))
        }
    }

    // MARK: - Public properties

    /// The stored object in memory.
    public var wrappedValue: Object {
        let key = Key(configuration: configuration ?? .global)

        if let value = Internals.Storage.shared.getValue(Object.self, forKey: key) {
            return value
        }

        // - Important: Reading, then building, then storing must not be three separate steps
        // with nothing holding them together — two concurrent readers could both miss, both run
        // the factory, and both store, so each would walk away with a different instance. This
        // wrapper's one promise is a single shared instance, so the insert below must resolve
        // the race and report the winner, discarding a loser's instance rather than returning
        // it.
        return Internals.Storage.shared.setValueIfAbsent(thunk(), forKey: key)
    }

    // MARK: - Private properties

    @_Container private var configuration: StoredObjectConfiguration?
    private let thunk: @Sendable () -> Object

    // MARK: - Inits

    ///
    /// Initializes a new `StoredObject` with the given object.
    ///
    /// - Parameter thunk: The object that will be stored in memory.
    ///
    public init(wrappedValue thunk: @autoclosure @escaping @Sendable () -> Object) {
        self.thunk = thunk
    }
}

// MARK: - DynamicStoredObject

extension StoredObject: DynamicStoredObject {

    func update(_ configuration: StoredObjectConfiguration) {
        self.configuration = configuration
    }
}
