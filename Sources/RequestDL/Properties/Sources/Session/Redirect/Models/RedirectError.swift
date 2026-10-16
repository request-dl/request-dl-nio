//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A redirect that could not be followed.
///
/// The same on every executor: `URLSession` and AsyncHTTPClient each have their own error for
/// these conditions, and neither is what a caller should have to catch to handle them.
///
/// ```swift
/// do {
///     try await DataTask { ... }.result()
/// } catch let error as RedirectError where error.reason == .cycleDetected {
///     // The server redirects in a circle.
/// }
/// ```
///
/// > Note: A redirect that is simply not followed (``Session/disableRedirect()``, or a
/// ``RedirectStrategy`` that answers with a decision to stop) is not an error: the response that
/// asked for it is the result.
public struct RedirectError: Error, Sendable, Hashable, CustomStringConvertible {

    /// Why the redirect could not be followed.
    public enum Reason: Sendable, Hashable {

        /// The chain is longer than the `max` given to ``Session/enableRedirectFollow(max:allowCycles:)``.
        case limitReached

        /// A redirect led back to a URL that had already been visited, and the session does not
        /// allow that (see `allowCycles` of ``Session/enableRedirectFollow(max:allowCycles:)``).
        case cycleDetected

        /// A ``RedirectStrategy`` answered with a decision to follow a URL that can't be parsed.
        ///
        /// The URL is not part of the error: an error's description tends to end up in logs, and
        /// the URL may carry credentials.
        case invalidURL
    }

    /// Why the redirect could not be followed.
    public let reason: Reason

    public var description: String {
        switch reason {
        case .limitReached:
            return "A redirect chain was longer than the limit set for it."

        case .cycleDetected:
            return "A redirect led back to a URL that had already been visited."

        case .invalidURL:
            return "A redirect strategy answered with a URL that can't be parsed."
        }
    }

    init(_ reason: Reason) {
        self.reason = reason
    }

    init(_ error: Internals.RedirectError) {
        switch error.reason {
        case .limitReached:
            self.init(.limitReached)

        case .cycleDetected:
            self.init(.cycleDetected)

        case .invalidURL:
            self.init(.invalidURL)
        }
    }
}
