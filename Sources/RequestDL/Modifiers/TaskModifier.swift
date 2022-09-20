import Foundation

public protocol TaskModifier {

    associatedtype Body: Task
    associatedtype Element

    func task(_ task: Body) async throws -> Element
}
