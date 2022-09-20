import Foundation

extension Modifiers {

    public struct MapError<Content: Task>: TaskModifier {

        public typealias Element = Content.Element

        let mapErrorHandler: (Error) throws -> Element

        init(mapErrorHandler: @escaping (Error) throws -> Element) {
            self.mapErrorHandler = mapErrorHandler
        }

        public func task(_ task: Content) async throws -> Element {
            do {
                return try await task.response()
            } catch {
                return try mapErrorHandler(error)
            }
        }
    }
}

extension Task {

    public func mapError(
        _ mapErrorHandler: @escaping (Error) throws -> Element
    ) -> ModifiedTask<Modifiers.MapError<Self>> {
        modify(Modifiers.MapError(mapErrorHandler: mapErrorHandler))
    }
}
