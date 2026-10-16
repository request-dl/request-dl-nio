//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    /// A redirect an executor could not follow, the same whichever executor it was.
    ///
    /// `.urlSession` raises these itself; for `.nio` they are what AsyncHTTPClient's own errors for
    /// the same conditions become (see ``translating(_:)``), at the one place those errors enter,
    /// so that nothing above an executor has to know which of the two it ran on. `RawTask` and
    /// `AsyncResponse` turn this into the public `RedirectError`.
    package struct RedirectError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        // MARK: - Inner types

        package enum Reason: Sendable, Hashable {

            /// The chain is longer than `Internals.RedirectConfiguration.follow(max:_:)`'s `max`.
            case limitReached

            /// A redirect would revisit a URL already visited, and cycles are not allowed.
            case cycleDetected

            /// A redirect strategy answered `.follow` with a URL that can't be parsed. The URL it
            /// answered with, when the executor knows it: AsyncHTTPClient does not say.
            case invalidURL(String?)
        }

        // MARK: - Internal properties

        package let reason: Reason

        package var description: String {
            switch reason {
            case .limitReached:
                return "A redirect chain was longer than the limit set for it."

            case .cycleDetected:
                return "A redirect led back to a URL that had already been visited."

            case .invalidURL:
                return "A redirect was to a URL that can't be parsed."
            }
        }

        // MARK: - Inits

        package init(_ reason: Reason) {
            self.reason = reason
        }
    }
}

#if canImport(NIOCore)

extension Internals.RedirectError {

    /// `error` as this type when it is AsyncHTTPClient's own for one of these conditions, and
    /// `error` itself otherwise.
    ///
    /// For an error raised while a request was in flight: the request URL was already parsed when
    /// the request was built, so an invalid URL at that point can only be a redirect's.
    package static func translating(_ error: any Error) -> any Error {
        guard let error = error as? HTTPClientError else {
            return error
        }

        switch error {
        case .redirectLimitReached:
            return Internals.RedirectError(.limitReached)

        case .redirectCycleDetected:
            return Internals.RedirectError(.cycleDetected)

        case .invalidURL:
            return Internals.RedirectError(.invalidURL(nil))

        default:
            return error
        }
    }
}

#endif
