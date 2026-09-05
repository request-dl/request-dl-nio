//
// See LICENSE for this package's licensing information.
//

/// Everything a ``RedirectStrategy`` is handed to decide whether -- and how -- to follow one
/// redirect.
public struct RedirectContext: Sendable {

    // MARK: - Public properties

    /// The request that would be sent to follow the redirect. See ``RedirectRequest`` for the
    /// rewrite rules already applied to it.
    public var redirectRequest: RedirectRequest

    /// The head of the response that triggered the redirect.
    public var response: ResponseHead

    /// Every request/response pair sent so far for this logical request, oldest first, including
    /// the one that produced ``response``.
    public var history: [RedirectHistoryEntry]

    /// How many redirects have already been followed for this logical request (equivalently,
    /// `history.count - 1`).
    ///
    /// - Important: There is no built-in redirect limit once a ``RedirectStrategy`` is
    /// configured -- enforce your own policy against this value (or `history`) to avoid an
    /// infinite redirect loop.
    public var redirectCount: Int

    // MARK: - Inits

    ///
    /// Initializes a new redirect context.
    ///
    /// - Parameters:
    ///    - redirectRequest: The request that would be sent to follow the redirect.
    ///    - response: The head of the response that triggered the redirect.
    ///    - history: Every request/response pair sent so far for this logical request.
    ///    - redirectCount: How many redirects have already been followed for this logical request.
    ///
    public init(
        redirectRequest: RedirectRequest,
        response: ResponseHead,
        history: [RedirectHistoryEntry],
        redirectCount: Int
    ) {
        self.redirectRequest = redirectRequest
        self.response = response
        self.history = history
        self.redirectCount = redirectCount
    }
}
