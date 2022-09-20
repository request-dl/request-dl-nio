import Foundation

extension Middlewares {

    public struct Detach<Element>: MiddlewareType {

        let detachHandler: (Result<Element, Error>) -> Void

        init(detachHandler: @escaping (Result<Element, Error>) -> Void) {
            self.detachHandler = detachHandler
        }

        public func received(_ result: Result<Element, Error>) {
            detachHandler(result)
        }
    }
}

extension Task {

    public func detach(
        _ handler: @escaping (Result<Element, Error>) -> Void
    ) -> InterceptedTask<Middlewares.Detach<Element>, Self> {
        intercept(Middlewares.Detach(detachHandler: handler))
    }
}
