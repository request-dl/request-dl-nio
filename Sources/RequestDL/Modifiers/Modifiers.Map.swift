import Foundation

extension Modifiers {

    public struct Map<Content: Task, NewElement>: TaskModifier {

        let mapHandler: (Content.Element) throws -> NewElement

        init(mapHandler: @escaping (Content.Element) throws -> NewElement) {
            self.mapHandler = mapHandler
        }

        public func task(_ task: Content) async throws -> NewElement {
            try mapHandler(await task.response())
        }
    }
}

extension Task {

    public func map<NewElement>(
        _ mapHandler: @escaping (Element) throws -> NewElement
    ) -> ModifiedTask<Modifiers.Map<Self, NewElement>> {
        modify(Modifiers.Map(mapHandler: mapHandler))
    }
}
