//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient

extension Internals {

    package enum RedirectConfiguration: Sendable {

        case disallow
        case follow(max: Int, allowCycles: Bool)

        /// Redirects are handed to a pluggable ``Internals/RedirectStrategy``. There is no
        /// built-in redirect-count/cycle limit in this mode -- it replaces, not composes with,
        /// `.follow`'s limits, mirroring `AsyncHTTPClient.HTTPClient.Configuration
        /// .RedirectConfiguration.strategy(_:)`, which this bridges to for the NIO executor. See
        /// `RequestDL.RedirectStrategy` for why.
        case strategy(any Internals.RedirectStrategy)

        // MARK: - Internal methods

        package func build() -> HTTPClient.Configuration.RedirectConfiguration {
            switch self {
            case .disallow:
                return .disallow
            case .follow(let max, let allowCycles):
                return .follow(max: max, allowCycles: allowCycles)
            case .strategy(let strategy):
                return .strategy(Internals.NIORedirectStrategyAdapter(strategy: strategy))
            }
        }
    }
}

// MARK: - Equatable

// `.strategy` carries an existential with no meaningful notion of equality, so -- like `NaN` --
// a `.strategy` value is never equal to any other value, including another `.strategy`. This is
// deliberate, matching AsyncHTTPClient's own `RedirectConfiguration.Mode`: a `Session` carrying a
// `.strategy` never matches a previously pooled client's `Internals.Session.Configuration` by
// equality (see ``Internals/RedirectStrategy``/`RequestDL.RedirectStrategy`'s own doc comment for
// the connection-pooling consequence), so every resolution gets a fresh client.
extension Internals.RedirectConfiguration: Equatable {

    package static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disallow, .disallow):
            return true
        case (.follow(let lhsMax, let lhsAllowCycles), .follow(let rhsMax, let rhsAllowCycles)):
            return lhsMax == rhsMax && lhsAllowCycles == rhsAllowCycles
        default:
            return false
        }
    }
}

// MARK: - Hashable

extension Internals.RedirectConfiguration: Hashable {

    package func hash(into hasher: inout Hasher) {
        switch self {
        case .disallow:
            hasher.combine(0)
        case .follow(let max, let allowCycles):
            hasher.combine(1)
            hasher.combine(max)
            hasher.combine(allowCycles)
        case .strategy:
            hasher.combine(2)
        }
    }
}
