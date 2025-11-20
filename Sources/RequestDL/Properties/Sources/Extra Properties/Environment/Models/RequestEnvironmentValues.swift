/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 ``RequestEnvironmentValues`` is a type that contains all of the environment values
 for a property hierarchy. It is accessible via a subscript on a property's ``PropertyEnvironment`` wrapper.
 */
public struct RequestEnvironmentValues: Sendable {

    private struct Entry: Sendable, CustomDebugStringConvertible {
        let value: Sendable
        let debugDescriptionBuilder: @Sendable (Sendable) -> String

        var debugDescription: String {
            debugDescriptionBuilder(value)
        }
    }

    @TaskLocal
    static var current = RequestEnvironmentValues()

    // MARK: - Private properties

    private var values = [ObjectIdentifier: Entry]()

    // MARK: - Inits

    init() {}

    // MARK: - Public methods

    /**
     Subscript for retrieving an `Value` for a given ``RequestEnvironmentKey`` type.

     - Parameter key: The ``RequestEnvironmentKey`` type to retrieve the `Value` for.
     - Returns: The `Value` in the environment for the given `Key`.
     */
    public subscript<Key: RequestEnvironmentKey>(key: Key.Type) -> Key.Value {
        get {
            guard
                let entry = values[ObjectIdentifier(key)],
                let value = entry.value as? Key.Value
            else { return Key.defaultValue }

            return value
        }
        set {
            values[ObjectIdentifier(key)] = .init(
                value: newValue,
                debugDescriptionBuilder: {
                    "\(key): \(String(reflecting: $0))"
                }
            )
        }
    }
}

extension RequestEnvironmentValues: CustomDebugStringConvertible {

    public var debugDescription: String {
        guard !values.isEmpty else {
            return "\(type(of: self))(empty)"
        }

        let entryStrings = values.map(\.value.debugDescription)
        return "\(type(of: self))(\n\t" + entryStrings.joined(separator: ",\n\t") + "\n)"
    }
}

@available(*, deprecated, renamed: "RequestEnvironmentValues")
public typealias PropertyEnvironmentValues = RequestEnvironmentValues
