//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Why a PAC script could not give an answer.
    ///
    /// The marker `RequestDL` rewraps into its public `ProxyAutoConfigurationError`, the same split
    /// `Internals.ResourceTimeoutError` and `Internals.NetworkPathUnsatisfiedError` use.
    package struct PACEvaluationFailure: Swift.Error, Sendable, Equatable {

        package enum Reason: Sendable, Equatable {
            /// The script's fetch and evaluation did not finish in the time allowed.
            case timedOut
            /// The script could not be fetched, or it did not parse or run, or it threw. CFNetwork
            /// reports these through one callback and does not say which it was.
            case failed
        }

        /// What went wrong.
        package let reason: Reason

        /// What the evaluator reported, when it said anything.
        package let details: String?

        package init(reason: Reason, details: String? = nil) {
            self.reason = reason
            self.details = details
        }
    }

    /// What asking a PAC script about a URL came to.
    ///
    /// `answered(nil)` is a script that said to connect directly. It is not the same as `failed`,
    /// which is a script that could not be asked, and the difference is what lets a caller decide
    /// what a failure should do.
    package enum PACResolution: Sendable, Equatable {
        case answered(Internals.Proxy?)
        case failed(PACEvaluationFailure)
        /// The caller was cancelled while the evaluation was still going.
        case cancelled
    }
}
