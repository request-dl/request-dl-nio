import Foundation

struct Resolver<Content: Request> {

    private let request: Content

    init(_ request: Content) {
        self.request = request
    }

    private func resolve() async -> Context {
        let context = Context(RootNode())
        await Content.makeRequest(request, context)
        return context
    }

    func make(_ delegate: DelegateProxy) async -> (URLSession, URLRequest) {
        let context = await resolve()

        guard let object = context.find(Url.Object.self) else {
            fatalError()
        }

        let sessionObject = context.find(Session.Object.self)

        var request = URLRequest(url: object.url)
        var configuration = sessionObject?.configuration.sessionConfiguration ?? .default

        context.make(&request, configuration: &configuration, delegate: delegate)

        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: sessionObject?.queue
        )

        return (session, request)
    }
}

extension Resolver {

    func debugPrint() async {
        let context = await resolve()
        context.debug()
    }
}
