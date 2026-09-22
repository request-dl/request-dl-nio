//
// See LICENSE for this package's licensing information.
//

#if os(iOS) || os(visionOS)
import Foundation
#endif

extension Internals {

    /// Mirrors `URLSessionConfiguration.MultipathServiceType`'s cases. AsyncHTTPClient only
    /// exposes a plain on/off `enableMultipath` flag on `HTTPClient.Configuration`, with no
    /// equivalent to the handover/interactive/aggregate distinction, so the collapse to `Bool`
    /// happens inline as `self != .none` at the one call site that needs it
    /// (`Internals.Session.Configuration.build()`) rather than through a `build()` method here:
    /// that mapping is lossy (4 cases to 1), not a 1:1 translation like the other `Internals`
    /// enums in this file's sibling models.
    ///
    /// `.urlSession` is the one executor that can express the distinction in full, via
    /// `urlSessionMultipathServiceType` below.
    package enum MultipathServiceType: Sendable, Hashable {
        case none
        case handover
        case interactive
        case aggregate

        #if os(iOS) || os(visionOS)
        /// The `URLSessionConfiguration.multipathServiceType` this maps onto: the 1:1 translation
        /// the NIO side has no way to express.
        ///
        /// Gated to iOS (which covers Mac Catalyst) and visionOS because that is exactly where the
        /// property exists. `NSURLSession.h` declares it
        /// `API_AVAILABLE(ios(11.0)) API_UNAVAILABLE(macos, watchos, tvos)`, so on macOS, tvOS and
        /// watchOS there is no multipath API on `URLSession` to translate to at all, and
        /// `buildURLSessionConfiguration()` correspondingly has nothing to set there.
        package var urlSessionMultipathServiceType: URLSessionConfiguration.MultipathServiceType {
            switch self {
            case .none: return .none
            case .handover: return .handover
            case .interactive: return .interactive
            case .aggregate: return .aggregate
            }
        }
        #endif
    }
}
