//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    package enum Decompression: Sendable {

        case disabled
        case enabled(algorithms: [any Internals.DecompressionAlgorithm], limit: Internals.Decompression.Limit)

        // MARK: - Internal properties

        /// Whether resolving this configuration to `.urlSession` requires this package to set its
        /// own `Accept-Encoding` header on every request: whether any configured algorithm isn't
        /// one CFNetwork already decodes transparently on its own (`gzip`/`deflate`/`br`).
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
        /// whenever a natively-decoded algorithm is anywhere in the configured list is always safe:
        /// whatever it leaves untouched (a custom algorithm, or nothing at all) is exactly what
        /// manual dispatch downstream is for.
        ///
        /// Unlike `.urlSession`, there is no all-or-nothing constraint here. `NIOHTTPResponseDecompressor`
        /// only ever reacts to a `Content-Encoding: gzip`/`deflate` response, so it can stay on
        /// alongside manual dispatch for anything else.
        ///
        /// - Important: Gated on `isNativelyDecodedByNIO`, not `contentEncodingValue`, since
        /// `NIOHTTPResponseDecompressor` is a single switch triggered purely by the response's own
        /// header, with no notion of which algorithm instance was configured. A genuinely custom
        /// algorithm that happens to declare `contentEncodingValue == "gzip"` must not enable this,
        /// or `async-http-client` would decode the response out from under it before manual
        /// dispatch ever got a chance to hand it over.
        #if canImport(NIOCore)
        package func build() -> HTTPClient.Decompression {
            switch self {
            case .disabled:
                return .disabled
            case .enabled(let algorithms, let limit):
                let hasNIONativeAlgorithm = algorithms.contains(where: \.isNativelyDecodedByNIO)
                return hasNIONativeAlgorithm ? .enabled(limit: limit.build()) : .disabled
            }
        }
        #endif
    }
}

// MARK: - Equatable

extension Internals.Decompression: Equatable {

    /// `any Internals.DecompressionAlgorithm` has no equality of its own, so this compares what
    /// actually drives observable behavior rather than instance identity.
    ///
    /// `contentEncodingValue` alone is *not* that. `isNativelyDecodedByNIO`/
    /// `isNativelyDecodedByURLSession`/`requiresURLSession` are deliberately per-conformer
    /// answers rather than checks against the wire value (see `Internals.DecompressionAlgorithm`),
    /// precisely so a genuinely custom algorithm declaring `contentEncodingValue == "gzip"` is
    /// told apart from the built-in `GzipAlgorithm` placeholder that shares that string. Those
    /// three are what `build()`/`requiresManualURLSessionHandling`/
    /// `Internals.Session.Configuration.nonURLSessionExecutorIncompatibilityReasons()` read, so
    /// they belong in this comparison too.
    ///
    /// That matters here and not only in the abstract: `Internals.ClientManager` keys its pooled
    /// clients on `Internals.Session.Configuration.==`, and `build()`'s answer is baked into the
    /// `HTTPClient` at construction time. Comparing only the wire value let a session configured
    /// with a custom "gzip" algorithm reuse a pooled client built with
    /// `NIOHTTPResponseDecompressor` switched on (or the reverse). Neither direction is benign:
    /// `async-http-client` decodes the body without stripping `Content-Encoding`, so manual
    /// dispatch would then run the custom algorithm a second time over already-decoded bytes,
    /// while the reverse leaves a natively-decoded session's body compressed with nothing left to
    /// decode it.
    ///
    /// Two configurations agreeing on all four still compare equal, so the common case (plain
    /// `.gzip`/`.deflate`) keeps pooling connections the way it always has, instead of paying
    /// `RedirectConfiguration.strategy`'s "never equal, fresh client every time" cost.
    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled):
            return true

        case (.enabled(let lAlgorithms, let lLimit), .enabled(let rAlgorithms, let rLimit)):
            guard lLimit == rLimit, lAlgorithms.count == rAlgorithms.count else {
                return false
            }

            return Set(lAlgorithms.map(AlgorithmIdentity.init)) == Set(rAlgorithms.map(AlgorithmIdentity.init))

        default:
            return false
        }
    }
}

extension Internals.Decompression {

    /// Everything about one algorithm that actually changes what this package does with a
    /// response, and therefore everything `==` above has to take into account.
    fileprivate struct AlgorithmIdentity: Hashable {

        let contentEncodingValue: String
        let requiresURLSession: Bool
        let isNativelyDecodedByURLSession: Bool
        let isNativelyDecodedByNIO: Bool

        init(_ algorithm: any Internals.DecompressionAlgorithm) {
            contentEncodingValue = algorithm.contentEncodingValue
            requiresURLSession = algorithm.requiresURLSession
            isNativelyDecodedByURLSession = algorithm.isNativelyDecodedByURLSession
            isNativelyDecodedByNIO = algorithm.isNativelyDecodedByNIO
        }
    }
}
