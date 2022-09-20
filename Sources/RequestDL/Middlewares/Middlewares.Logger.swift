import Foundation

extension Middlewares {

    public struct Logger: MiddlewareType {

        let isLogActive: Bool

        init(_ isActive: Bool) {
            isLogActive = isActive
        }

        public func received(_ result: Result<TaskResult<Data>, Error>) {
            guard isLogActive else {
                return
            }

            switch result {
            case .failure(let error):
                print("[REQUEST] Failure: \(error)")
            case .success(let result):
                print("[REQUEST] Success: \(result.response)")
                print("[REQUEST] Data: \(String(data: result.data, encoding: .utf8) ?? "Couldn't decode using UTF8")")
            }
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Middlewares.Logger, Self> {
        intercept(Middlewares.Logger(isActive))
    }
}
