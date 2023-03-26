/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

struct Resolver<Content: Property> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    private func resolve() async throws -> Context {
        let context = Context(RootNode())
        try await Content.makeProperty(content, context)
        return context
    }

    func make() async throws -> (RequestDLInternals.Session, Request) {
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
            request: Request(url: object.baseURL.absoluteString),
            configuration: sessionObject?.configuration ?? .init()
        )

        try await context.make(make)

        let session = try await RequestDLInternals.Session(
            provider: sessionObject?.provider ?? .shared,
            configuration: make.configuration
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
