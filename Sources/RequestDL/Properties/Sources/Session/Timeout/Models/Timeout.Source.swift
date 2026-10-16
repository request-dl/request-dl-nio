//
// See LICENSE for this package's licensing information.
//

extension Timeout {

    ///
    /// A set of options representing the types of timeout available for each request.
    ///
    /// Use the static properties of this struct to set the timeout interval for requests and resources.
    ///
    /// 1. `connect`: How long establishing the connection may take. The default value is 30s. Only the
    ///    executors built on SwiftNIO have that phase to limit: `.urlSession` ignores it.
    /// 2. `read`: How long a request may go without a byte moving in either direction. The default
    ///    value is 60s, and `.infinity` removes it.
    /// 3. `resource`: A total end-to-end deadline, covering connection, redirects, and the entire body transfer.
    /// 4. `all`: Defines the same timeout interval for both connect and read. It deliberately excludes `resource`,
    ///    since that means something different (a ceiling on the *whole* request) than the other two.
    ///
    /// In the example below, a request is made to the Google's website with the timeout for all types.
    ///
    /// ```swift
    /// DataTask {
    ///     BaseURL("google.com")
    ///     Timeout(.seconds(60), for: .all)
    /// }
    /// ```
    ///
    public struct Source: Sendable, OptionSet {

        // MARK: - Public static properties

        /// How long establishing the connection may take.
        ///
        /// Only the executors built on SwiftNIO have a connection phase to limit; `.urlSession`
        /// ignores it, and says so in the log when it is set apart from ``read``.
        public static let connect = Source(rawValue: 1 << 0)

        /// How long a request may go without a byte moving, in either direction: the request body
        /// going out, the response head or body coming in. Every byte starts it over.
        ///
        /// RequestDL's own, the same on every executor, and not counting the time the application
        /// holds the exchange back (suspended through a ``RequestController``, or waiting for the
        /// body to be read). A request that goes quiet for longer fails with ``ReadTimeoutError``.
        /// 60 seconds when not set; `Timeout(.infinity, for: .read)` removes it.
        public static let read = Source(rawValue: 1 << 1)

        /// A total end-to-end deadline for the request, mirroring
        /// `URLSessionConfiguration.timeoutIntervalForResource`: covers connecting, following any
        /// redirects, and streaming the entire response body, all as one budget. Enforced by
        /// RequestDL itself, since neither AsyncHTTPClient's `Timeout` nor `URLSessionConfiguration`'s
        /// own per-phase timeouts offer a single knob for this.
        ///
        /// Not included in ``all``: unlike `connect`/`read`, this isn't a per-phase timeout, so
        /// bundling it into `.all` would silently give every existing `.all` caller a
        /// resource-wide deadline they never asked for.
        public static let resource = Source(rawValue: 1 << 2)

        /// Defines same timeout interval for `request` and `resource`
        public static let all: Self = [.connect, .read]

        // MARK: - Public properties

        public let rawValue: UInt8

        // MARK: - Inits

        ///
        /// Initializes a new timeout source with the given raw value.
        ///
        /// - parameter rawValue: The raw value to use for the timeout source.
        ///
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}
