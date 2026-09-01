//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension Session {

    /// Mirrors `URLSessionConfiguration.MultipathServiceType`. AsyncHTTPClient only exposes a
    /// plain on/off `enableMultipath` flag, with no equivalent to `URLSession`'s handover/
    /// interactive/aggregate distinction, so every case other than ``none`` collapses to the same
    /// "multipath enabled" behavior underneath. Kept as a 4-case enum anyway, rather than a
    /// `Bool`, so a caller migrating from `URLSessionConfiguration` doesn't have to translate
    /// their intent by hand, and so a future AsyncHTTPClient release that adds real granularity
    /// has somewhere to grow into without a source break here.
    public enum MultipathServiceType: Sendable, Hashable {
        case none
        case handover
        case interactive
        case aggregate

        // MARK: - Internal methods

        func build() -> Internals.MultipathServiceType {
            switch self {
            case .none:
                return .none
            case .handover:
                return .handover
            case .interactive:
                return .interactive
            case .aggregate:
                return .aggregate
            }
        }
    }
}
