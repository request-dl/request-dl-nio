//
// See LICENSE for this package's licensing information.
//

/// The ``RequestEnvironmentKey`` protocol defines a type that can be used as a key to
/// retrieve an `Value` from ``RequestEnvironmentValues``.
public protocol RequestEnvironmentKey<Value>: Sendable {

    associatedtype Value: Sendable

    /// The default value for this ``RequestEnvironmentKey``.
    static var defaultValue: Value { get }
}
