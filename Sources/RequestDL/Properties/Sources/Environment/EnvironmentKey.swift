/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}
