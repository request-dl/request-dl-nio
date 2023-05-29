/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `PropertyEnvironmentKey` protocol defines a type that can be used as a key to
 retrieve an `Value` from `PropertyEnvironmentValues`.
 */
public protocol PropertyEnvironmentKey<Value>: Sendable {

    associatedtype Value: Sendable

    /// The default value for this `PropertyEnvironmentKey`.
    static var defaultValue: Value { get }
}

@available(*, deprecated, renamed: "PropertyEnvironmentKey")
public typealias EnvironmentKey = PropertyEnvironmentKey
