import Foundation

extension Modifiers {

    public struct KeyPath<Content: Task>: TaskModifier where Content.Element == TaskResult<Data> {

        let keyPath: String

        init(_ keyPath: Swift.KeyPath<AbstractKeyPath, String>) {
            self.keyPath = AbstractKeyPath()[keyPath: keyPath]
        }

        public func task(_ task: Content) async throws -> TaskResult<Data> {
            let result = try await task.response()

            guard
                let dictonary = try JSONSerialization.jsonObject(with: result.data, options: []) as? [String: Any],
                let value = dictonary[keyPath]
            else { return result }

            return .init(
                response: result.response,
                data: try JSONSerialization.data(
                    withJSONObject: value,
                    options: .fragmentsAllowed
                )
            )
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func keyPath(_ keyPath: KeyPath<AbstractKeyPath, String>) -> ModifiedTask<Modifiers.KeyPath<Self>> {
        modify(Modifiers.KeyPath(keyPath))
    }
}
