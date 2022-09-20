import Foundation

extension Modifiers {

    public struct FlatMap<Content: Task, NewElement>: TaskModifier {

        private let flatMapHandler: (Result<Content.Element, Error>) throws -> NewElement

        init(flatMapHandler: @escaping (Result<Content.Element, Error>) throws -> NewElement) {
            self.flatMapHandler = flatMapHandler
        }

        public func task(_ task: Content) async throws -> NewElement {
            switch await mapResponseIntoResult(task) {
            case .failure(let error):
                throw error
            case .success(let map):
                switch map {
                case .processed(let mapped):
                    return mapped
                case .original(let original):
                    return try flatMapHandler(.success(original))
                }
            }
        }
    }
}

private extension Modifiers.FlatMap {

    enum Map {
        case original(Content.Element)
        case processed(NewElement)
    }
}

private extension Modifiers.FlatMap {

    func mapResponseIntoResult(_ task: Content) async -> Result<Map, Error> {
        do {
            return .success(.original(try await task.response()))
        } catch {
            return mapErrorIntoResult(error)
        }
    }

    func mapErrorIntoResult(_ error: Error) -> Result<Map, Error> {
        do {
            return .success(.processed(try flatMapHandler(.failure(error))))
        } catch {
            return .failure(error)
        }
    }
}

extension Task {

    public func flatMap<NewElement>(
        _ flatMapHandler: @escaping (Result<Element, Error>) throws -> NewElement
    ) -> ModifiedTask<Modifiers.FlatMap<Self, NewElement>> {
        modify(Modifiers.FlatMap(flatMapHandler: flatMapHandler))
    }
}
