/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol RequestTaskModifier<Input, Output>: Sendable {

    typealias Content = _RequestTaskModifier_Content<Self>

    associatedtype Input: Sendable

    associatedtype Output: Sendable

    func body(_ task: Self.Content) async throws -> Output
}
