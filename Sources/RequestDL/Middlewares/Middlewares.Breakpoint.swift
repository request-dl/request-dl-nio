import Foundation

extension Middlewares {

    public struct Breakpoint<Element>: MiddlewareType {

        init() {}

        public func received(_ result: Result<Element, Error>) {
            raise(SIGTRAP)
        }
    }
}

extension Task {

    public func breakpoint() -> InterceptedTask<Middlewares.Breakpoint<Element>, Self> {
        intercept(Middlewares.Breakpoint())
    }
}
