/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `TaskEnvironmentKey` protocol defines a type that can be used as a key to
 retrieve an `Value` from `TaskEnvironmentValues`.
 */
public protocol TaskEnvironmentKey: Sendable {

    associatedtype Value: Sendable

    /// The default value for this `TaskEnvironmentKey`.
    static var defaultValue: Value { get }
}
