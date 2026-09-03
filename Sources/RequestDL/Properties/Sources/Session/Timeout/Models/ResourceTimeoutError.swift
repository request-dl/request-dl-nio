//
// See LICENSE for this package's licensing information.
//

/// An error thrown when a request exceeds ``Timeout/Source/resource``'s deadline -- the total
/// time budgeted for connecting, following redirects, and streaming the entire response body,
/// all together.
///
/// Unlike ``Timeout/Source/connect``/``Timeout/Source/read``, which AsyncHTTPClient enforces
/// per phase on its own, RequestDL enforces this one itself: it races the request end to end
/// against the configured deadline and cancels it the same way dropping the response or
/// cancelling the enclosing `Task` already would, the moment the deadline passes -- whether
/// that's still during connection/redirects or partway through the body.
public struct ResourceTimeoutError: Error, Sendable {

    // MARK: - Inits

    init() {}
}

// MARK: - CustomStringConvertible

extension ResourceTimeoutError: CustomStringConvertible {

    public var description: String {
        "RequestDL cancelled this request: it exceeded the Timeout(_:for: .resource) deadline before completing."
    }
}
