//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension DownloadResumptionError {

    /// The public face of the error a continuation that isn't the rest of the representation raises
    /// inside the executors, whichever of them it came from.
    init(_ error: Internals.DownloadResumptionMismatchError) {
        switch error.reason {
        case .representationChanged:
            self.init(.representationChanged)
        case .contentRangeMismatch:
            self.init(.contentRangeMismatch)
        case .validatorMismatch:
            self.init(.validatorMismatch)
        case .contentCoded:
            self.init(.contentCoded)
        case .unsatisfiableRange:
            self.init(.unsatisfiableRange)
        case .unexpectedStatus(let status):
            self.init(.unexpectedStatus(status))
        }
    }
}
