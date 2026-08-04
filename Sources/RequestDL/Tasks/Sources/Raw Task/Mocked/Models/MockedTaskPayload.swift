//
// See LICENSE for this package's licensing information.
//

protocol MockedTaskPayload<Element>: Sendable {

    associatedtype Element: Sendable

    func result(_ environment: RequestEnvironmentValues) async throws -> Element
}
