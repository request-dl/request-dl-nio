/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

struct Resolver<Content: Property> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    private func resolve() async -> Context {
        let context = Context(RootNode())
        await Content.makeProperty(content, context)
        return context
    }

    func make(_ delegate: DelegateProxy) async throws -> (HTTPClient, HTTPRequest) {
        let context = await resolve()

        guard let object = context.find(BaseURL.Object.self) else {
            fatalError(
                """
                Failed to find the required BaseURL object in the context.
                """
            )
        }

        let sessionObject = context.find(Session.Object.self)

        let make = Make(
            request: HTTPRequest(url: object.baseURL.absoluteString),
            configuration: sessionObject?.configuration ?? .init(tlsConfiguration: .clientDefault),
            delegate: delegate
        )

        context.make(make)

        let session = HTTPClient(
            eventLoopGroupProvider: sessionObject?.eventLoopGroup ?? .createNew,
            configuration: make.configuration
        )

        return (session, make.request)
    }
}

extension Resolver {

    func debugPrint() async {
        let context = await resolve()
        context.debug()
    }
}
