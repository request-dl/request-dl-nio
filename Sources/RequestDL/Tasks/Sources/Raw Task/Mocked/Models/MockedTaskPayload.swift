/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol MockedTaskPayload<Element>: Sendable {

    associatedtype Element: Sendable

    func result() async throws -> Element
}
