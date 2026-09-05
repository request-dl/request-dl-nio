//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Adapts a `RequestDL.RedirectStrategy` to `Internals.RedirectStrategy`, translating between
/// this module's public request/response types and the ones `Internals` -- shared by both
/// transports -- can reference without depending back on this module.
struct InternalsRedirectStrategyAdapter: Internals.RedirectStrategy {

    // MARK: - Internal properties

    let strategy: any RedirectStrategy

    // MARK: - Internal methods

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        let decision = try strategy.redirectDecision(for: .init(context))

        switch decision {
        case .doNotFollow:
            return .doNotFollow
        case .follow(let redirectRequest):
            return .follow(.init(redirectRequest))
        }
    }
}

// MARK: - RedirectRequest extension

extension RedirectRequest {

    fileprivate init(_ request: Internals.RedirectRequest) {
        self.init(
            url: request.url,
            method: request.method,
            headers: .init(request.headers),
            hasBody: request.hasBody
        )
    }
}

extension Internals.RedirectRequest {

    fileprivate init(_ request: RedirectRequest) {
        self.init(
            url: request.url,
            method: request.method,
            headers: request.headers.build(),
            hasBody: request.hasBody
        )
    }
}

// MARK: - RedirectHistoryEntry extension

extension RedirectHistoryEntry {

    fileprivate init(_ entry: Internals.RedirectHistoryEntry) {
        self.init(
            request: .init(entry.request),
            response: .init(entry.response)
        )
    }
}

// MARK: - RedirectContext extension

extension RedirectContext {

    fileprivate init(_ context: Internals.RedirectContext) {
        self.init(
            redirectRequest: .init(context.redirectRequest),
            response: .init(context.response),
            history: context.history.map(RedirectHistoryEntry.init),
            redirectCount: context.redirectCount
        )
    }
}
