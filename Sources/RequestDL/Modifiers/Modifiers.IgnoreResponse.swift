import Foundation

extension Modifiers {

    public struct IgnoreResponse<Content: Task, Element>: TaskModifier where Content.Element == TaskResult<Element> {

        init() {}

        public func task(_ task: Content) async throws -> Element {
            try await task.response().data
        }
    }
}

extension Task {

    public func ignoreResponse<T>() -> ModifiedTask<Modifiers.IgnoreResponse<Self, T>> where Element == TaskResult<T> {
        modify(Modifiers.IgnoreResponse())
    }
}
