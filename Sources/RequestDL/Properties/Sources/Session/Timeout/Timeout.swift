//
// See LICENSE for this package's licensing information.
//

/// `Timeout` is a struct that defines the request timeout for a connect, read, or the whole
/// resource end to end (see ``Timeout/Source/resource``).
///
/// To create an instance of `Timeout`, initialize it with the time interval and which source to be limited.
///
/// ```swift
/// Timeout(.seconds(40), for: .connect)
/// ```
///
/// In the example below, a request is made to Google's website with the timeout for all types.
///
/// ```swift
/// DataTask {
///     BaseURL("google.com")
///     Timeout(.seconds(60), for: .all)
/// }
///
/// ```
///
/// > Note: A request timeout is the amount of time a client will wait for a response from the server
/// before terminating the connection. The timeout parameter is the duration of time before the timeout
/// occurs, and the source parameter specifies the type of timeout to be applied
///
/// ## What read means
///
/// ``Timeout/Source/read`` is how long a request may go without a single byte moving, in either
/// direction: the request body going out, the response head or body coming in. Every byte starts
/// it over, and a request that goes quiet for longer than it fails with ``ReadTimeoutError``.
///
/// It is RequestDL's own, the same on every executor, and it is not counting while the
/// application is the one holding the exchange back: the time a transfer spends suspended through a
/// ``RequestController``, or waiting for the body to be read, does not count against the server.
///
/// Without a `Timeout` for ``Timeout/Source/read``, a request fails once it has been silent for
/// 60 seconds. A body that stays silent for longer than that, such as an event stream without
/// heartbeats, needs a larger value, or none:
///
/// ```swift
/// Timeout(.infinity, for: .read)
/// ```
///
/// ``Timeout/Source/connect`` is not part of this. It limits how long the connection may take to
/// be established, and only the executors built on SwiftNIO have that phase to limit:
/// `.urlSession` ignores it.
public struct Timeout: Property {

    private struct Node: PropertyNode {

        let timeout: UnitTime
        let source: Source

        func make(_ make: inout Make) async throws {
            if source.contains(.connect) {
                make.sessionConfiguration.timeout.connect = timeout.nanoseconds
            }

            if source.contains(.read) {
                make.sessionConfiguration.timeout.read = timeout.nanoseconds
            }

            if source.contains(.resource) {
                make.sessionConfiguration.timeout.resource = timeout.nanoseconds
            }
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let timeout: UnitTime
    let source: Source

    // MARK: - Inits

    ///
    /// Initializes a new instance of `Timeout`.
    ///
    /// - Parameters:
    ///    - timeout: The duration of time before the timeout occurs.
    ///    - source: The type of timeout to be applied.
    ///
    /// - Returns: A new instance of `Timeout`.
    ///
    /// > Note: By default, the `source` parameter is set to `.all`.
    ///
    /// > Important: `timeout` must not be negative. A negative duration is a mistake in the code
    /// that wrote it, and the request would otherwise start with its time already spent, so this
    /// traps. A value too large to count saturates at ``UnitTime/infinity`` instead.
    public init(_ timeout: UnitTime, for source: Source = .all) {
        precondition(
            timeout >= .zero,
            "Timeout cannot be negative, got \(timeout.nanoseconds) nanoseconds."
        )

        self.timeout = timeout
        self.source = source
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Timeout>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                timeout: property.timeout,
                source: property.source
            )
        )
    }
}
