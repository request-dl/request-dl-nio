//
// See LICENSE for this package's licensing information.
//

/// A task that is intercepted by an ``RequestTaskInterceptor``.
///
/// A ``InterceptedRequestTask`` is created by applying a ``RequestTask/interceptor(_:)`` to a base ``RequestTask``.
public struct InterceptedRequestTask<Interceptor: RequestTaskInterceptor>: RequestTask {

    public typealias Element = Interceptor.Element

    // MARK: - Internal properties

    let task: any RequestTask<Element>
    let interceptor: Interceptor

    // MARK: - Public methods

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> Element {
        do {
            let result = try await task._result(environment: environment)
            interceptor.output(.success(result))
            return result
        } catch {
            interceptor.output(.failure(error))
            throw error
        }
    }
}
