//
// See LICENSE for this package's licensing information.
//

/// An error thrown when a request goes quiet for longer than ``Timeout/Source/read`` allows:
/// not a single byte of the request body went out or of the response came in for that long.
///
/// RequestDL measures this itself, so it is the same error on every executor. It does not count
/// the time the application held the exchange back, by suspending it or by not reading the body
/// yet. A request that must stay silent for longer than the default 60 seconds takes
/// `Timeout(.infinity, for: .read)`, or a larger value.
///
/// The request is cancelled the same way dropping the response or cancelling the enclosing `Task`
/// would cancel it.
public struct ReadTimeoutError: Error, Sendable {

    // MARK: - Inits

    init() {}
}

// MARK: - CustomStringConvertible

extension ReadTimeoutError: CustomStringConvertible {

    public var description: String {
        "RequestDL cancelled this request: nothing was sent or received on it for longer than the Timeout(_:for: .read) allows."
    }
}
