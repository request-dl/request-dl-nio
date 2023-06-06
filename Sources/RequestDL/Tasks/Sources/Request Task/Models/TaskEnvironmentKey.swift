/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol TaskEnvironmentKey: Sendable {

    associatedtype Value: Sendable

    static var defaultValue: Value { get }
}
