//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Internals-layer counterpart to `RequestDL.RedirectHistoryEntry`.
    package struct RedirectHistoryEntry: Sendable {

        package var request: Internals.RedirectRequest
        package var response: Internals.ResponseHead

        package init(
            request: Internals.RedirectRequest,
            response: Internals.ResponseHead
        ) {
            self.request = request
            self.response = response
        }
    }
}
