//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Internals-layer counterpart to `RequestDL.RedirectContext`.
    package struct RedirectContext: Sendable {

        package var redirectRequest: Internals.RedirectRequest
        package var response: Internals.ResponseHead
        package var history: [Internals.RedirectHistoryEntry]
        package var redirectCount: Int

        package init(
            redirectRequest: Internals.RedirectRequest,
            response: Internals.ResponseHead,
            history: [Internals.RedirectHistoryEntry],
            redirectCount: Int
        ) {
            self.redirectRequest = redirectRequest
            self.response = response
            self.history = history
            self.redirectCount = redirectCount
        }
    }
}
