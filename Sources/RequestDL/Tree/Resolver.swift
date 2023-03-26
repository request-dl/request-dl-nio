/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Resolver<Content: Property> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    private func resolve() async throws  -> Context {
        let context = Context(RootNode())
        try await Content.makeProperty(content, context)
        return context
    }

    func make(_ delegate: DelegateProxy) async throws -> (URLSession, URLRequest) {
        let context = try await resolve()

        guard let object = context.find(BaseURL.Object.self) else {
            fatalError(
                """
                Failed to find the required BaseURL object in the context.
                """
            )
        }

        let sessionObject = context.find(Session.Object.self)

        let make = Make(
            request: URLRequest(url: object.baseURL),
            configuration: sessionObject?.configuration ?? .default,
            delegate: delegate
        )

        try await context.make(make)

        let session = URLSession(
            configuration: make.configuration,
            delegate: delegate,
            delegateQueue: sessionObject?.queue
        )

        return (session, make.request)
    }
}

extension Resolver {

    func debugPrint() async throws {
        let context = try await resolve()
        context.debug()
    }
}
