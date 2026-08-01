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

        // Reading, then building, then storing used to be three steps with nothing holding
        // them together: two concurrent readers both missed, both ran the factory, and both
        // stored, so each walked away with the instance it had built. That is the one promise
        // this wrapper makes, and it was the one it could not keep.
        //
        // The insert resolves the race and reports the winner, so a loser's instance is
        // discarded rather than returned.
        return Internals.Storage.shared.setValueIfAbsent(thunk(), forKey: key)
    }

    // MARK: - Private properties

    @_Container private var configuration: StoredObjectConfiguration?
    private let thunk: @Sendable () -> Object

    // MARK: - Inits

    ///
    /// Initializes a new `StoredObject` with the given object.
    ///
    /// - Parameter wrappedValue: The object that will be stored in memory.
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
