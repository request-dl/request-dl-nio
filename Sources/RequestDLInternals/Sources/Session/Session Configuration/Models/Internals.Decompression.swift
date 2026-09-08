//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient

extension Internals {

    package enum Decompression: Sendable {

        case disabled
        case enabled(algorithms: [any Internals.DecompressionAlgorithm], limit: Internals.Decompression.Limit)

        // MARK: - Internal properties

        /// Whether resolving this configuration to `.urlSession` requires this package to set its
        /// own `Accept-Encoding` header on every request -- i.e. whether any configured algorithm
        /// isn't one CFNetwork already decodes transparently on its own (`gzip`/`deflate`/`br`).
        ///
        /// `.disabled` also needs this: URLSession's automatic decoding can only be switched off
        /// by taking over `Accept-Encoding` ourselves (`identity`), the same mechanism a genuinely
        /// custom algorithm needs.
        package var requiresManualURLSessionHandling: Bool {
            switch self {
            case .disabled:
                return true
            case .enabled(let algorithms, _):
                return !algorithms.allSatisfy(\.isNativelyDecodedByURLSession)
            }
        }

        /// The full set of configured algorithms, `[]` for `.disabled`. Used both to build
        /// `Accept-Encoding` and, on the manual-dispatch path, to match an arriving
        /// `Content-Encoding` against one of them.
        package var algorithms: [any Internals.DecompressionAlgorithm] {
            switch self {
            case .disabled:
                return []
            case .enabled(let algorithms, _):
                return algorithms
            }
        }

        // MARK: - Internal methods

        /// `async-http-client`'s own native gzip/deflate decoder strips `Content-Encoding` once it
        /// successfully decodes a response (see `NIOHTTPResponseDecompressor`), so enabling it
        /// whenever a natively-decoded algorithm is anywhere in the configured list is always safe
        /// -- whatever it leaves untouched (a custom algorithm, or nothing at all) is exactly what
        /// manual dispatch downstream is for. Unlike `.urlSession`, there is no all-or-nothing
        /// constraint here: `NIOHTTPResponseDecompressor` only ever reacts to a `Content-Encoding:
        /// gzip`/`deflate` response, so it can stay on alongside manual dispatch for anything else.
        ///
        /// - Important: Gated on `isNativelyDecodedByNIO`, not `contentEncodingValue` --
        /// `NIOHTTPResponseDecompressor` is a single switch triggered purely by the response's own
        /// header, with no notion of which algorithm instance was configured. A genuinely custom
        /// algorithm that happens to declare `contentEncodingValue == "gzip"` must not enable this,
        /// or `async-http-client` would decode the response out from under it before manual
        /// dispatch ever got a chance to hand it over.
        package func build() -> HTTPClient.Decompression {
            switch self {
            case .disabled:
                return .disabled
            case .enabled(let algorithms, let limit):
                let hasNIONativeAlgorithm = algorithms.contains(where: \.isNativelyDecodedByNIO)
                return hasNIONativeAlgorithm ? .enabled(limit: limit.build()) : .disabled
            }
        }
    }
}

// MARK: - Equatable

extension Internals.Decompression: Equatable {

    /// `any Internals.DecompressionAlgorithm` has no equality of its own, so this compares what
    /// actually drives observable behavior -- the set of `Content-Encoding` values configured,
    /// plus the limit -- rather than instance identity. Two configurations with the same set
    /// produce byte-identical `HTTPClient.Configuration`/`Accept-Encoding` output, so treating
    /// them as equal keeps the common case (plain `.gzip`/`.deflate`) pooling connections the way
    /// it always has, instead of paying `RedirectConfiguration.strategy`'s "never equal, fresh
    /// client every time" cost for a case that doesn't need it.
    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled):
            return true

        case (.enabled(let lAlgorithms, let lLimit), .enabled(let rAlgorithms, let rLimit)):
            guard lLimit == rLimit, lAlgorithms.count == rAlgorithms.count else {
                return false
            }

            return Set(lAlgorithms.map(\.contentEncodingValue)) == Set(rAlgorithms.map(\.contentEncodingValue))

        default:
            return false
        }
    }
}
