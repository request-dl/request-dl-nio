import Foundation

extension Modifiers {

    public struct StatusCode<Content: Task>: TaskModifier where Content.Element == TaskResult<Data> {

        private let statusCodeValidation: StatusCodeValidation

        init(_ statusCodeValidation: StatusCodeValidation) {
            self.statusCodeValidation = statusCodeValidation
        }

        public func task(_ task: Content) async throws -> TaskResult<Data> {
            let result = try await task.response()

            guard
                let httpResponse = result.response as? HTTPURLResponse,
                statusCodeValidation.validate(statusCode: httpResponse.statusCode)
            else {
                throw StatusCodeValidationError(data: result.data)
            }

            return result
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func statusCode(_ statusCodeValidation: StatusCodeValidation) -> ModifiedTask<Modifiers.StatusCode<Self>> {
        modify(Modifiers.StatusCode(statusCodeValidation))
    }
}
