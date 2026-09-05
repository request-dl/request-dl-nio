//
// See LICENSE for this package's licensing information.
//

/// One request/response pair already sent while following redirects for a single logical
/// request. See ``RedirectContext/history``.
public struct RedirectHistoryEntry: Sendable {

    // MARK: - Public properties

    /// The request that was sent.
    public var request: RedirectRequest

    /// The head of the response it received.
    public var response: ResponseHead

    // MARK: - Inits

    ///
    /// Initializes a new redirect history entry.
    ///
    /// - Parameters:
    ///    - request: The request that was sent.
    ///    - response: The head of the response it received.
    ///
    public init(
        request: RedirectRequest,
        response: ResponseHead
    ) {
        self.request = request
        self.response = response
    }
}
