//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// An error thrown when the proxy auto-configuration (PAC) script that decides a request's proxy
/// could not be asked, and the request's policy is to fail: ``SystemProxy/PACFailurePolicy/fail``,
/// or ``SystemProxy/PACFailurePolicy/lastKnown(orElse:)`` with a script that never answered and
/// ``SystemProxy/PACFailurePolicy/Fallback/fail`` to fall back on.
///
/// Under the default policy, ``SystemProxy/PACFailurePolicy/direct``, the request is sent
/// directly instead and the failure is only logged, which on a network that requires a proxy
/// sends it around that proxy.
///
/// A failure is remembered for a few seconds, so the requests that follow it fail at once with
/// this same error instead of each waiting for the script again.
public struct ProxyAutoConfigurationError: Error, Sendable {

    /// Why the script could not be asked.
    public enum Reason: Sendable, Hashable {
        /// Fetching and evaluating the script did not finish in time.
        case timedOut
        /// The script could not be fetched, did not parse or run, or threw. The system reports
        /// these through one callback and does not say which it was; see ``details``.
        case failed

        init(_ reason: Internals.PACEvaluationFailure.Reason) {
            switch reason {
            case .timedOut:
                self = .timedOut

            case .failed:
                self = .failed
            }
        }
    }

    // MARK: - Public properties

    /// Why the script could not be asked.
    public let reason: Reason

    /// What the system reported, when it reported anything.
    public let details: String?

    // MARK: - Inits

    init(_ failure: Internals.PACEvaluationFailure) {
        self.reason = Reason(failure.reason)
        self.details = failure.details
    }
}

// MARK: - CustomStringConvertible

extension ProxyAutoConfigurationError: CustomStringConvertible {

    public var description: String {
        let reasonDescription: String

        switch reason {
        case .timedOut:
            reasonDescription = "evaluating it did not finish in time"

        case .failed:
            reasonDescription = "it could not be fetched or run"
        }

        let detailsNote = details.map { " (\($0))" } ?? ""

        return """
            RequestDL could not decide the proxy of this request: the proxy auto-configuration \
            script was not usable, because \(reasonDescription)\(detailsNote). The request was not \
            sent, because its SystemProxy policy is to fail when the script cannot be used.
            """
    }
}
